%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 25, 2012 by Alex Robson

-module(vrpl_message_util).

-export([ 
			bert_encode/1,
			bert_decode/1,
			default_serializers/0,
			encode/2,
			decode/2,
			json_encode/1,
			json_decode/1
		]).

bert_encode(Term) ->
	term_to_binary(Term).

bert_decode(Binary) ->
	binary_to_term(Binary).

json_encode(PropList) ->
	json:encode(PropList).

json_decode(Json) ->
	json:decode(Json).

default_serializers() ->
	Json_Coders = { 
		fun(X) -> json_encode(X) end,
		fun(X) -> json_decode(X) end 
	},
	Bert_Coders = {
		fun(X) -> bert_encode(X) end,
		fun(X) -> bert_decode(X) end 			
	},
	Plain_Coders = {
		fun(X) -> amqp_util:to_bin(X) end,
		fun(X) -> X end
	},
	[
		{<<"application/json">>, Json_Coders },
		{<<"application/x-erlang-binary">>, Bert_Coders },
		{<<"text/plain">>, Plain_Coders}
	].

decode(Msg, ContentType) ->
	BinType = amqp_util:to_bin(ContentType),
	{_, Deserialize} = vrpl_configuration:get_serializer(BinType),
	Deserialize(Msg).

encode(Msg, Props) ->
	ContentType = proplists:get_value(content_type, Props, <<"text/plain">>),
	BinType = amqp_util:to_bin(ContentType),
	{Serialize, _} = vrpl_configuration:get_serializer(BinType),
	Serialize(Msg).
