%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl_app).
-behaviour(application).
-export([start/2, stop/1]).

-define(SERVER, ?MODULE).

%%===================================================================
%%% API
%%===================================================================

start(_Type, _Args) ->
	vrpl_process:init(),
	vorperl_sup:start_link().

stop(_State) ->
	ok.