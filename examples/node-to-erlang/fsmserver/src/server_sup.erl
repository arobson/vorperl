%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 29, 2012 by Alex Robson

-module(server_sup).

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

    Router = create_child_spec(router, worker, permanent, 2000, []),
    Reservations = create_child_spec(reservation_sup, supervisor, permanent, 2000, []),
    
    {ok, {SupFlags, [Router, Reservations]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.