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

    Config = create_child_spec(vrpl_configuration, worker, permanent, 2000, []),
    Exchanges =create_child_spec(vrpl_exchanges, supervisor, permanent, 2000, []),
    Queues =create_child_spec(vrpl_queues, supervisor, permanent, 2000, []),
    Connections = create_child_spec(vrpl_connection, worker, permanent, 2000, []),
    Channels = create_child_spec(vrpl_channel, worker, permanent, 2000, []),

    {ok, {SupFlags, [Config, Connections, Channels, Exchanges, Queues]}}.

%%===================================================================
%%% Internal functions
%%===================================================================

create_child_spec(Child, Type, Restart, Shutdown, Args) ->
    {Child, { Child, start_link, Args }, Restart, Shutdown, Type, [Child]}.