%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 29, 2012 by Alex Robson

-module(router).

-behavior(gen_server).

-export([create_topology/0]).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {resources = dict:new()}).

-include("amqp.hrl").

%%===================================================================
%%% API
%%===================================================================

create_topology() ->
	% 192.168.1.106
	vorperl:broker([{host, "localhost"}]),
	vorperl:route_to(fun(X) -> gen_server:cast(?SERVER, X) end),
	vorperl:exchange("reservation", [{type, "fanout"}]),
	vorperl:queue("server-q1", [auto_delete]),
	vorperl:bind("reservation", "server-q1", "").

%%===================================================================
%%% Callbacks
%%===================================================================

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
	create_topology(),
	{ok, #state{}}.

handle_call(stop, _From, State) ->
  	{stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  	{reply, State, State};
 
handle_call(_Request, _From, State) ->
  	{reply, ok, State}.

handle_cast(#envelope{}=Envelope, State) ->
	Ack = Envelope#envelope.ack,
	NewState = 
		case Envelope#envelope.correlation_id of
			undefined -> 
				io:format("Bad message: ~p ~n", [Envelope#envelope.body]),
				State;
			Id -> route_to_resource(Id, Envelope, State)
		end,			
	Ack(),
	{noreply, NewState};

handle_cast({new_resource, Id, Pid}, State) ->
	io:format("Resouce ~p added. ~n", [Id]),
	Resources = State#state.resources,
	{noreply, State#state{ resources = dict:store(Id, Pid, Resources) }};

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

create(Id) ->
	reservation_sup:new_resource(Id).

reply(R, Envelope) ->
	Reply = Envelope#envelope.reply,
	Reply(R, "", [{headers, [{"replyTo", Envelope#envelope.id}]}]).

route_to_resource(Id, Envelope, State) ->
	Resources = State#state.resources,
	case dict:is_key(Id, Resources) of
		true -> 
			Pid = dict:fetch(Id, Resources),
			send(Pid, Id, Envelope),
			State;
		false -> 
			Pid = create(Id),
			send(Pid, Id, Envelope),
			State#state{ resources = dict:store(Id, Pid, Resources)}
	end.

send(Pid, _Id, Envelope) ->
	{Command, UserId} = translate(Envelope),
	Reply = fun(R) -> reply(R, Envelope) end,
	gen_fsm:send_event(Pid, {Command, UserId, Reply }).
	
translate(Envelope) ->
	case Envelope#envelope.content_type of
		<<"application/json">> ->
			parse_body(Envelope#envelope.body);
		<<"application/x-erlang-binary">> ->
			parse_body(Envelope#envelope.body)
	end.

parse_body(Body) ->
	Command = proplists:get_value(messageType, Body),
	User = proplists:get_value(userId, Body),
	{
		atomize(Command), 
		User
	}.

atomize(X) when is_atom(X) -> X;
atomize(X) when is_list(X) -> list_to_atom(X);
atomize(X) when is_bitstring(X) -> atomize(bitstring_to_list(X));
atomize(X) -> X.