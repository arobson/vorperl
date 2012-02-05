%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created February 3, 2012 by Alex Robson

-module(resterly_app).

-behaviour(application).

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
	start([],[]).

start(_StartType, _StartArgs) ->
    api:start_link(),
    resterly_sup:start_link().

stop(_State) ->
    ok.
