-module(yaterl_gen_mod).

-export([
         behaviour_info/1,

         dispatch/1,
         reply/1,
         ack/1
        ]).

-include("yate.hrl").

%%====================================================================
%% Behaviour Definition Callback
%%====================================================================

%%% @doc: <b>BEHAVIOUR CALLBACK</b> return yaterl_gen_mod callbacks list
%%% 
%%% <b>connection_available</b>: custom on connection available callback
%%% Example 1:
%%% ```
%%% connection_available() ->
%%%    do_nothing.
%%% '''
%%%
%%% Example 2:
%%% ```
%%% connection_available() ->
%%%    start_subscribe_sequence.
%%% '''
%%%
%%% <b>subscribe_config</b>: return a subscribe config list.
%%% Example:
%%% ```
%%% subscribe_config() ->
%%%    [{"call.execute", install, 20},
%%%     {"custom.message", watch}].
%%% '''
%%% <b>subscribe_error</b>: custom subscribe error handling.
%%% Example:
%%% ```
%%% subscribe_error(LastRequested, LastReceived) ->
%%%    error_logger:error_msg("Subscribe Error: ...", [LastRequested, LastReceived]),
%%%    erlang:halt(-1).
%%% '''
%%%
%%% <b>handle_watch_message</b>: watched message handling (return value ignored).
%%% Example:
%%% ```
%%% handle_watch_message(YateMsg) ->
%%%    error_logger:info_msg("Watched Event Received: ~p~n", [YateEvent]).
%%% '''
%%%
%%% <b>handle_install_message</b>: installed message handling (return value replied to yate)
%%% Example:
%%% ```
%%% handle_install_message(YateMsg) ->
%%%    Name = yate_message:name(YateMessage),
%%%    Direction = yate_event:direction(YateMessage),
%%%    Called = yate_message:param(called, YateMessage)
%%%    case {Name, Direction, Called} of
%%%        {"call.route", incoming, "123"} ->
%%%            route_to_dial(YateMessage);
%%%        _AnyOther -> log(YateMessage)
%%%    end.
%%% '''
behaviour_info(callbacks) ->
    [{connection_available, 0},
     {subscribe_config, 0},
     {subscribe_error, 2},
     {handle_watch_message, 1},
     {handle_install_message, 1}];
behaviour_info(_Other) ->
    undefined.

%%====================================================================
%% API
%%====================================================================

%%% @doc: immediately send a yate message
dispatch(YateMessage) when is_record(YateMessage, yate_event) ->
    Data = yate_encode:to_binary(YateMessage),
    yaterl_connection_mgr:send_binary_data(Data).

%%% @doc: create a binary encoded reply (handled yate message) to be 
%%%       returned from an handle_install_message
reply(YateMessage) when is_record(YateMessage, yate_event) ->
    Reply = yate_message:reply(YateMessage, true),
    _Data = yate_encode:to_binary(Reply),
    {yate_binary_reply, _Data}.

%%% @doc: create a binary encoded ack (unhandled yate message) to be 
%%%       returned from an handle_install_message
ack(YateMessage) when is_record(YateMessage, yate_event) ->
    Reply = yate_message:reply(YateMessage, false),
    _Data = yate_encode:to_binary(Reply),
    {yate_binary_reply, _Data}.

