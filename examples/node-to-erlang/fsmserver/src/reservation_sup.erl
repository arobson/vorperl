%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 29, 2012 by Alex Robson

-module(reservation_sup).
-behaviour(supervisor).
-export([start_link/0, init/1, new_resource/1]).

-define(SERVER, ?MODULE).
-define(CHILD, reservation).

%%===================================================================
%%% API
%%===================================================================

start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

new_resource(Id) ->
	{ok, Pid} = supervisor:start_child(?SERVER, [Id]),
	Pid.

init([]) ->
	RestartStrategy = simple_one_for_one,
    MaxRestarts = 5,
    MaxSecondsBetweenRestarts = 60,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    Child = create_child_spec(?CHILD, worker, permanent, 2000, []),

    {ok, {SupFlags, [Child]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.