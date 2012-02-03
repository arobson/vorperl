%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 29, 2012 by Alex Robson

-module(reservation).

-behavior(gen_fsm).

%% gen_fsm callbacks
-export([start_link/1, init/1, handle_event/3,
         handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% states
-export([available/2, reserved/2]).

-define(SERVER, ?MODULE).
-define(ROUTER, router).

-record(state, {id, reserved_by, history=[]}).

%%%===================================================================
%%% API
%%%===================================================================


%%===================================================================
%%% States
%%===================================================================
available({reserve, Id, Reply}, State) ->
    io:format("Reserving resource ~p.~n", [State#state.id]),
    Reply([{result, reservation_created}, {resource, State#state.id}, {user, Id}]),
    {next_state, reserved, State#state{ reserved_by=Id }};

available({release, Id, Reply}, State) ->
    Reply([{result, ignored}, {resource, State#state.id}, {user, Id}]),
    {next_state, available, State};

available({status, Id, Reply}, State) ->
    Reply([{result, available}, {resource, State#state.id}, {user, Id}]),
    {next_state, available, State}.

reserved({reserve, Id, Reply}, State) ->
    if
        reserved_by =:= Id ->
            Reply([{result, already_reserved}, {resource, State#state.id}, {user, Id}]);
        true ->
            Reply([{result, unavailable}, {resource, State#state.id}, {user, Id}])
    end,    
    {next_state, reserved, State#state{ reserved_by=Id} };

reserved({release, Id, Reply}, State) ->
    Reply([{result, reservation_released}, {resource, State#state.id}, {user, Id}]),
    {next_state, available, State#state{ 
        reserved_by=undefined,
        history=lists:append([State#state.reserved_by],State#state.history)
    }};

reserved({status, Id, Reply}, State) ->
    Reply([{result, reserved}, {resource, State#state.id}, {user, Id}]),
    {next_state, reserved, State}.

%%===================================================================
%%% Callbacks
%%===================================================================

start_link(Id) ->
    gen_fsm:start_link(?MODULE, [Id], []).

init([Id]) ->
    io:format("Resource ~p created. ~n", [Id]),
    gen_server:cast(?ROUTER, {new_resource, Id, self()}),
    {ok, available, #state{id = Id}}.

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
