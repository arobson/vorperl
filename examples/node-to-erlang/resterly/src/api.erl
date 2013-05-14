%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created February 3, 2012 by Alex Robson

-module(api).

-export([start_link/0, stop/0]).

-include_lib("amqp.hrl").

start_link() ->
	io:format("Trying to start misultin~n"),
	{ok, _Pid} = misultin:start_link([
		{port, 9000},
		{loop, fun(Req) -> handle_request(Req) end}
		]).
	
stop() ->
	euuid:stop(),
	misultin:stop().

handle_request(Req) ->
	io:format("request~n"),
	handle( 
		Req:get(method),
		Req:resource([lowercase, urldecode]),
		Req
	).

handle('GET', ["reservation", ReservationId], Req) ->
	Id = euuid:format(euuid:v1()),
	Message = [{messageType, "status"}, {userId, "erl"}],
	Opts = [
		{content_type, "application/json"},
		{correlation_id, ReservationId},
		{reply_to, "rest"},
		{id, Id}
	],
	Pid = self(),
	Callback = fun(X, Req) ->
		io:format("on callback, sending ~p ~n", [X]),
		Req:ok("hiya, world!"),
		Pid ! ok
	end,

	%callback_server:add_callback(Id, Callback, Req),
	register(list_to_atom(Id), self()),
	vorperl:send("reservation", Message, "", Opts),
	receive
		Json -> Callback(Json, Req)
	after 
		1000 -> Req:respond(400, "BOO HIGGITY")
	end;

handle(_X, _Y, Req) ->
	Req:respond(404, "Go away |: |").