%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created February 3, 2012 by Alex Robson

-module(callback_server).

-behavior(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-export([add_callback/3, run_callback/2, on_message/1]).

-record(state, {callbacks = dict:new(), requests = dict:new()}).

-include_lib("amqp.hrl").

%%===================================================================
%%% API
%%===================================================================

add_callback(Id, Callback, Req) ->
	gen_server:cast(?SERVER, {new_callback, Id, Callback, Req}).

run_callback(Id, Result) ->
	gen_server:cast(?SERVER, {callback, Id, Result}).

on_message(E) ->
	io:format("incoming reply~n"),
	Id = proplists:get_value(<<"replyTo">>, E#envelope.headers, undefined),
	Body = E#envelope.body,
	Json = message_util:json_encode(Body),
	case whereis(list_to_atom(bitstring_to_list(Id))) of
		undefined -> ok;
		Pid -> Pid ! Json
	end,
	%run_callback(Id, Json),
	Ack = E#envelope.ack,
	Ack().

%%===================================================================
%%% Callbacks
%%===================================================================

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
	vorperl:broker(),
	vorperl:topology(
		{exchange, "rest", [autoDelete, {type, "direct"}]},
		{queue, "rest", [autoDelete, {route_to, {?SERVER, on_message}}]},
		""
	),
	vorperl:exchange("reservation", [{type, "fanout"}]),
	euuid:start(),
	io:format("starting callback server~n"),
	{ok, #state{}}.

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  {reply, State, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast({new_callback, Id, Callback, Req}, State) ->
	io:format("Adding callback for ~p ~n", [Id]),
	Callbacks = State#state.callbacks,
	Requests = State#state.requests,
	NewState = State#state{ 
		callbacks = dict:store(Id, Callback, Callbacks),
		requests = dict:store(Id, Req, Requests)
	},
  	{noreply, NewState};

handle_cast({callback, Id, Result}, State) ->
	io:format("Calling callback for ~p ~n", [Id]),
	Callbacks = State#state.callbacks,
	Requests = State#state.requests,
	case dict:is_key(Id, Callbacks) of
		true ->
			Callback = dict:fetch(Id, Callbacks),
			Req = dict:fetch(Id, Requests),
			Callback(Result, Req),
			{noreply, State#state{ 
				callbacks = dict:erase(Id, Callbacks),
				requests = dict:erase(Id, Requests)
			}};
		_ ->
			io:format("No callback for ~p ~n", [Id]),
  			{noreply, State}
	end;

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.
 
terminate(_Reason, _State) ->
  ok.
 
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%===================================================================
%%% Internal functions
%%===================================================================