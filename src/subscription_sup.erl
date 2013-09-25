%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 20, 2012 by Alex Robson

-module(subscription_sup).
-behaviour(supervisor).
-export([start_link/0, init/1, start_subscription/4]).

-define(SERVER, ?MODULE).

%%===================================================================
%%% API
%%===================================================================

start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_subscription(Queue, RouteTo, Channel, Providers) ->
	supervisor:start_child(?SERVER, [Queue, RouteTo, Channel, Providers]).

init([]) ->
	RestartStrategy = simple_one_for_one,
    MaxRestarts = 5,
    MaxSecondsBetweenRestarts = 60,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
    Subscription = create_child_spec(queue_subscriber, worker, permanent, 2000, []),

    {ok, {SupFlags, [Subscription]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.