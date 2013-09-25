%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 25, 2012 by Alex Robson

-module(message_util).

-export([ 
			bert_encode/1,
			bert_decode/1,
			default_providers/0,
			encode_message/3,
			json_encode/1,
			json_decode/1,
			json_format/1,
			json_strip/1
		]).

bert_encode(Term) ->
	term_to_binary(Term).

bert_decode(Binary) ->
	binary_to_term(Binary).

json_encode(PropList) ->
	Format = json_format(PropList),
	io:format("~p~n",[Format]),
	jiffy:encode(Format).


json_format(X) when is_list(X) ->
	{json_prep(amqp_util:to_bitstring(X))};
json_format(X) -> X.

json_prep([]) -> [];
json_prep([H|T]) when is_list(H) ->
	[{json_prep(H)}] ++ json_prep(T);
json_prep([{X,Y}|T]) ->
	lists:append([{json_prep(X), json_prep(Y)}], json_prep(T));
json_prep(X) -> json_format(X).

json_decode(Json) ->
	json_strip(jiffy:decode(Json)).

json_strip([]) -> [];
json_strip([{[_|_]=H}|T]) -> 
	[json_strip(H)] ++ json_strip(T);
json_strip({[{X,Y}|T]}) -> 
	json_strip([{X,Y}|T]);
json_strip([{X,Y}|T]) -> 
	lists:append([json_strip({X, Y})], json_strip(T));
json_strip({X,Y}) ->
	NewX = to_atom(X),
	{NewX, json_strip(Y)};
json_strip(X) when is_bitstring(X) -> bitstring_to_list(X);
json_strip(X) -> X.

to_atom(X) when is_bitstring(X) -> to_atom(bitstring_to_list(X));
to_atom([H|L]) -> list_to_atom([string:to_lower(H)|L]).

default_providers() ->
	Json_Coders = { 
		fun(X) -> json_encode(X) end,
		fun(X) -> json_decode(X) end 
	},
	Bert_Coders = {
		fun(X) -> bert_encode(X) end,
		fun(X) -> bert_decode(X) end 			
	},
	dict:from_list([
		{<<"application/json">>, Json_Coders },
		{<<"application/x-erlang-binary">>, Bert_Coders }
	]).

encode_message(Msg, Flags, Providers) ->
	ContentType = proplists:get_value(content_type, Flags, <<"text/plain">>),
	case dict:is_key(ContentType, Providers) of
		true -> 
			{Encoder, _} = dict:fetch( ContentType, Providers ),
			Encoder(Msg);
		_ -> amqp_util:to_bin(Msg)
	end.