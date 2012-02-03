REBAR=$(shell which rebar || ./rebar)
SYNC_PATH = $(ERL_LIBS)/sync

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
		if test -d $(SYNC_PATH); \
		then exec erl -pa $(PWD)/deps/*/ebin -pa $(PWD)/ebin -boot start_sasl -s sync -s lager -s vorperl -run server_app; \
		else exec erl -pa $(PWD)/deps/*/ebin -pa $(PWD)/ebin -boot start_sasl -s reloader -s lager -s vorperl -run server_app; \
		fi
