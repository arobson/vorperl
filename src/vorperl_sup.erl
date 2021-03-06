%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl_sup).
-behaviour(supervisor).
-export([start_link/0, init/1]).

-define(SERVER, ?MODULE).

%%===================================================================
%%% API
%%===================================================================

start_link() ->
	supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
	RestartStrategy = one_for_one,
    MaxRestarts = 2,
    MaxSecondsBetweenRestarts = 60,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Amqp = create_child_spec(vorperl_server, worker, permanent, 2000, []),
    Connections = create_child_spec(connection_pool, worker, permanent, 2000, []),
    Subscriptions =create_child_spec(subscription_sup, supervisor, permanent, 2000, []),

    {ok, {SupFlags, [Amqp, Connections, Subscriptions]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.