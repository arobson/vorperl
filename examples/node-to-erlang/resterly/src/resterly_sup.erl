%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created February 3, 2012 by Alex Robson

-module(resterly_sup).

-behavior(supervisor).

-export([start_link/0, init/1]).

-define(SERVER, ?MODULE).

%%===================================================================
%%% API
%%===================================================================

%%===================================================================
%%% Callbacks
%%===================================================================
start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
	RestartStrategy = one_for_one,
    MaxRestarts = 2,
    MaxSecondsBetweenRestarts = 60,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Callbacks = create_child_spec(callback_server, worker, permanent, 2000, []),
    Api = create_child_spec(api, worker, permanent, 2000, []),
    
    {ok, {SupFlags, [Callbacks]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.