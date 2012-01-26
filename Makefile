REBAR=`which rebar || ./rebar`

all: deps compile

compile:
		@$(REBAR) compile

app:
		@$(REBAR) compile skip_deps=true

deps:
		@$(REBAR) get-deps

clean:
		@$(REBAR) clean

distclean: clean
		@$(REBAR) delete-deps

test: app
		@$(REBAR) eunit skip_deps=true

start:
		exec erl -pa $(PWD)/deps/*/ebin -pa $(PWD)/ebin -boot start_sasl -s reloader -s lager -run connection_pool start_link -run vorperl start_link
