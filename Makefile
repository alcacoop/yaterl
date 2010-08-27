REBAR=./rel/rebar

help:
	@echo "YATErl building tool."
	@echo "Usage: "
	@echo "       ./make {compile|clean}"        
	@echo
	@echo "       ./make test"  
	@echo
	@echo "       ./make doc"
	@echo
	@echo

test: FORCE compile
	${REBAR} ct

doc: FORCE
	${REBAR} doc

compile:
	${REBAR} compile

clean:
	${REBAR} clean

FORCE:
