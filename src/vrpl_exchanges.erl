%%% @author Alex Robson
%%% @copyright 2014
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 26, 2014 by Alex Robson

-module(vrpl_exchanges).
-behaviour(supervisor).
-export([start_link/0, init/1, add/2]).

-define(SERVER, ?MODULE).

%%===================================================================
%%% API
%%===================================================================

start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

add(Exchange, Properties) ->
	supervisor:start_child(?SERVER, [Exchange, Properties]).

init([]) ->
	RestartStrategy = simple_one_for_one,
    MaxRestarts = 5,
    MaxSecondsBetweenRestarts = 60,
    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    Exchange = create_child_spec(vrpl_exchange, worker, permanent, 2000, []),
    {ok, {SupFlags, [Exchange]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.