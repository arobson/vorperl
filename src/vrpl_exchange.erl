%%% @author Alex Robson
%%% @copyright 2014
%%% @doc
%%%		Manage publishing and tracking of returns and confirms.
%%%		Also tracks unpublished messages in the event of channel failure
%%%		so that messages can be retried on a new channel after re-establishing
%%%		a failed connection and/or channel.
%%% @end
%%% @license MIT
%%% Created January 26, 2014 by Alex Robson

-module(vrpl_exchange).

-behavior(gen_server).

-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([define/2, publish/4]).

-record(state, {channel, props, name, monitor}).

-include("amqp.hrl").

-define(DEFAULT, "default").
-define(TABLE, vrpl_unpublished).
-define(SERVER, ?MODULE).

%% ===================================================================
%%  API
%% ===================================================================

define(Exchange, Properties) ->
	vrpl_configuration:store_exchange(Exchange, Properties),
	case vrpl_process:get({exchange, Exchange}) of
		undefined -> 
			vrpl_exchanges:add(Exchange, Properties);
		Pid when is_pid(Pid) -> Pid
	end.

publish(Exchange, Message, RoutingKey, MessageProperties) ->
	Envelope = get_envelope(Exchange, Message, RoutingKey, MessageProperties),
	Pid = vrpl_process:get({exchange, Exchange}),
	gen_server:call(Pid, {publish, Envelope}).

%%===================================================================
%%% gen_server
%%===================================================================

start_link(Exchange, Properties) ->
	gen_server:start_link(?MODULE, [Exchange, Properties], []).

init([Exchange, Properties]) ->
	init_ets(),
	vrpl_process:store({exchange, Exchange}),
	State = setup(Exchange, Properties),
	{ok, State#state{props = Properties}}.

handle_call(stop, _From, State) ->
	{stop, normal, stopped, State};

handle_call({publish, Envelope}, _From, #state{channel=Channel, name=Exchange}=State) ->
	publish(Exchange, Channel, Envelope),
	{reply, ok, State};
 
handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _Info}, #state{monitor = Ref}=State) ->
	{noreply, handle_channel_shutdown(State)};

handle_info({_BasicReturn, _Content}, State) ->
	% Reason = BasicReturn#'basic.return'.reply_text,
	% ReturnEnvelope = amqp_util:prep_return(BasicReturn, Content),
	% case State#state.return_handler of
	% 	Handler when is_function(Handler, 2) -> 
	% 		Handler(Reason, ReturnEnvelope);
	% 	Handler when is_pid(Handler) -> 
	% 		Handler ! {on_return, Reason, ReturnEnvelope};
	% 	{M, F} -> apply(M, F, [Reason, ReturnEnvelope])
	% end,
	{noreply, State};

handle_info(_Info, State) ->
	{noreply, State}.
 
terminate(_Reason, _State) ->
	ok.
 
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ===================================================================
%%  Internal
%% ===================================================================

ensure_monitor(#state{channel=Channel, monitor=Monitor}=State) ->
	case Monitor of
		undefined -> ok;
		_ -> demonitor(Monitor)
	end,
	Ref = monitor(process, Channel),
	State#state{monitor=Ref}.

handle_channel_shutdown(#state{name=Exchange, props=Props}) ->
	State2 = setup(Exchange, Props),
	Channel = State2#state.channel,
	Pending = get_unpublished(Exchange),
	[republish(Exchange, Channel, Message, Sequence) || 
		{_, Sequence, Message} <- Pending],
	State2.

get_envelope(Exchange, Message, RoutingKey, MessageProperties) ->
	Props = vrpl_configuration:get_exchange(Exchange),
	MsgProps = amqp_util:parse_proplist(MessageProperties),
	Body = vrpl_message_util:encode(Message, Props),
	{AmqpProps, PublishData} = amqp_util:prep_message(Exchange, RoutingKey, MsgProps, Props),
	{PublishData, #amqp_msg{props = AmqpProps, payload = Body}}.

publish(Exchange, Channel, {PublishData, Message}=Envelope) -> 
	Sequence = amqp_channel:next_publish_seqno(Channel),
	add_unpublished(Exchange, Sequence, Envelope),
	amqp_channel:cast(Channel, PublishData, Message).

republish(Exchange, Channel, Message, Sequence) -> 
	remove_unpublished(Exchange, Sequence),
	publish(Exchange, Channel, Message).

setup(#state{name=Exchange, props=Props, channel=Channel}=State) ->
	Config = amqp_util:parse_proplist(Props),
	BinaryName = amqp_util:to_bitstring(Exchange),
	Declaration = amqp_util:exchange_declare(BinaryName, Config),
	amqp_channel:call(Channel, Declaration),
	State;

setup(Exchange) ->
	Props = vrpl_configuration:get_exchange(Exchange),
	setup(Exchange, Props).

setup(Exchange, Props) ->
	Broker = proplists:get_value(broker, Props, ?DEFAULT),
	Channel = vrpl_channel:get({exchange, Exchange}, Broker),
	setup(Exchange, Props, Channel).

setup(Exchange, Props, Channel) ->
	State = #state{name = Exchange, props = Props, channel = Channel},
	amqp_channel:register_return_handler(Channel, self()),
	ensure_monitor(setup(State)).

%% ===================================================================
%%  ETS
%%  Wrappers for interactions with ETS. Currently used to track
%%  unconfirmed messages across exchanges. Done this way to prevent
%%  loss of a message outside of total node failure. Keys should be
%%  unique and prevent possibilities of collision.
%% ===================================================================

init_ets() ->
	case ets:info(?TABLE) of
		undefined ->
			ets:new(?TABLE, [ordered_set, public, named_table, {read_concurrency, true}, {write_concurrency, true}]);
		_ -> ok
	end.

add_unpublished(Exchange, Sequence, Envelope) ->
	ets:insert(?TABLE, {{Exchange, Sequence}, Envelope}).

remove_unpublished(Exchange, Sequence) ->
	ets:delete(?TABLE, {Exchange, Sequence}).

get_unpublished(ExchangeName) ->
	case ets:lookup(?TABLE, {{ExchangeName, '$1'}, '$2'}) of
		[] -> [];
		Matches -> [ {ExchangeName, Sequence, Envelope} || [Sequence, Envelope] <- Matches ]
	end.
