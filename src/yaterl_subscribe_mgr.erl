%% yaterl_subscribe_mgr: yaterl subscribe manager
%%
%% Copyright (C) 2009-2010 - Alca Società Cooperativa <info@alcacoop.it>
%%
%% Author: Luca Greco <luca.greco@alcacoop.it>
%%
%% This program is free software: you can redistribute it and/or modify
%% it under the terms of the GNU Lesser General Public License as published by
%% the Free Software Foundation, either version 3 of the License, or
%% (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% General Public License for more details.
%%
%% You should have received a copy of the GNU Lessel General Public License
%% along with this program.  If not, see <http://www.gnu.org/licenses/>.

%% @author Luca Greco <luca.greco@alcacoop.it>
%% @copyright 2009-2010 Alca Societa' Cooperativa

%% @doc '{@module}' is a gen_fsm erlang process that 
%%      manage yate message subscribe sequence and 
%%      resolve routing of incoming subscribed yate messages.
%%
%%  == UML State Machine Diagram ==
%%
%%      <img src="img/yaterl_subscribe_mgr_fsm.png" alt="Yaterl subscribe manager FSM"
%%           title="Yaterl subscribe manager FSM"/>

-module(yaterl_subscribe_mgr).

-behaviour(gen_fsm).

%% API
-export([
         start_link/0,
         start_subscribe_sequence/0,
         handle_yate_event/1,
         resolve_custom_module/1
        ]).

%% gen_fsm callbacks
-export([init/1, 
         'STARTED'/2, 'SUBSCRIBE'/2,
         handle_sync_event/4,
         terminate/3, code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {subscribe_queue, subscribe_config}).

%%====================================================================
%% API
%%====================================================================

%% @doc: Starts the server
%% @spec: () -> {ok,Pid} | ignore | {error,Error}
start_link() ->
    gen_fsm:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc: Start the configured subscribe sequence on the active connection
%% @spec: () -> ok
start_subscribe_sequence() ->
    gen_fsm:send_event(?SERVER, start_subscribe_sequence).

%% @doc: Handle an incoming yate subscribe event (watch, unwatch, install, uninstall)
%%       during 'REGISTERING' state
%% @spec: (YateEvent::yate_event()) -> ok
handle_yate_event(YateEvent) ->
    gen_fsm:send_event(?SERVER, {handle_yate_event, YateEvent}).

%% @doc: Resolve subscribed yate_message routing 
%% @spec: (YateEvent::yate_event()) -> ResolvedPath
%% where
%%    ResolvedPath = InstallPath | InstallPriorityPath | WatchPath
%%    InstallPath = {MessageName::string(), install}
%%    InstallPriorityPath = {MessageName::string(), install, Priority::int()}
%%    WatchPath = {MessageName::string(), watch}
resolve_custom_module(YateEvent) ->
    gen_fsm:sync_send_all_state_event(?SERVER, {resolve_custom_module, YateEvent}).

%%====================================================================
%% gen_fsm callbacks
%%====================================================================

%% @doc: <b>[GEN_FSM CALLBACK]</b> Initiates the server
%% @spec: ([]) -> {ok, State} | {ok, State, Timeout} | ignore | {stop, Reason}
init([]) ->
    {ok, 'STARTED', #state{subscribe_config=yaterl_config:yaterl_message_subscribe_configlist()}}.

%% @doc <b>[GEN_FSM CALLBACK]</b> handle 'STARTED' state events
%% @see start_subscribe_sequence/0
'STARTED'(start_subscribe_sequence, State) ->
    yaterl_logger:info_msg("start_subscribe_sequence~n"),
    {NextState, NewStateData} = case start_request_queue(State) of
                                    {continue, StateData} -> {'SUBSCRIBE', StateData};
                                    {finish, StateData} -> {'COMPLETED', StateData}
                                end,
    {next_state, NextState, NewStateData}.

%% @doc <b>[GEN_FSM CALLBACK]</b> handle 'SUBSCRIBE' state events
%% @see handle_yate_event/0
'SUBSCRIBE'({handle_yate_event, _YateEvent}, State) ->
    {NextState, NewStateData} = case run_request_queue(State) of 
        {continue, StateData} -> {'SUBSCRIBE', StateData};
        {finish, StateData} -> {'COMPLETED', StateData}
    end,
    {next_state, NextState, NewStateData}.

%% @doc <b>[GEN_FSM CALLBACK]</b> handle sync event on any state
%% @see resolve_custom_module/1
handle_sync_event({resolve_custom_module, YateEvent}, _From, StateName, StateData) ->
    SubscribeConfig = StateData#state.subscribe_config,
    Reply = case proplists:lookup(yate_message:name(YateEvent), SubscribeConfig) of
                none -> unknown;
                {_MessageName, install, _Priority} -> install;
                {_MessageName, install} -> install;
                {_MessageName, watch} -> watch
    end,
    {reply, Reply, StateName, StateData}.

%% @doc: <b>[GEN_FSM CALLBACK]</b> Handling terminate sequence. 
%% It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%% 
%% @spec: (_Reason, _StateName, _State) -> ok
terminate(_Reason, _StateName, _State) ->
    ok.

%% @doc: <b>[GEN_SERVER CALLBACK]</b> Convert process state when code is changed
%% @spec: (OldVsn, StateName, State, Extra) -> {ok, NewState}
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

start_request_queue(State) ->
    Queue = queue:from_list(State#state.subscribe_config),
    yaterl_logger:info_msg("SUBSCRIBE QUEUE: ~p~n", [Queue]),
    SubscribeState = State#state{subscribe_queue=Queue},
    run_request_queue(SubscribeState).

run_request_queue(State) ->
    {Out, NewQueue} = queue:out(State#state.subscribe_queue),
    NewState = State#state{subscribe_queue = NewQueue},
    yaterl_logger:info_msg("SEND FROM SUBSCRIBE QUEUE: ~p~n", [Out]),
    case Out of
        empty -> {finish, NewState }; 
        {value, V} -> send_subscribe_request(V),
                      {continue, NewState}
    end.
    

send_subscribe_request({MessageName, install}) ->
    YateEvent = yate_event:new(install, [{name, MessageName}]),
    send_to_yate(YateEvent),
    ok;
send_subscribe_request({MessageName, install, Priority}) ->
    YateEvent = yate_event:new(install, [{name, MessageName},{priority, Priority}]),
    send_to_yate(YateEvent),
    ok;
send_subscribe_request({MessageName, watch}) ->
    YateEvent = yate_event:new(watch, [{name, MessageName}]),
    send_to_yate(YateEvent),
    ok.

send_to_yate(YateEvent) ->
    yaterl_logger:info_msg("SEND TO YATE: ~p~n", [YateEvent]),
    yaterl_connection_mgr:send_binary_data(yate_encode:to_binary(YateEvent)).
