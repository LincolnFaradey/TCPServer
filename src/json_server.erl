-module (json_server).
-behaviour (gen_server).
-include ("db_info.hrl").

-export ([start_link/0, check_data/1]).

%%gen_server callbacks
-export ([init/1, handle_call/3,
 		handle_cast/2, handle_info/2,
  		terminate/2, code_change/3]).
-define (PORT, 1477).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [?PORT], []).


init([Port]) ->
	process_flag(trap_exit, true),
	{ok, Listen} = gen_tcp:listen(Port, 
		[{active, false},
		{recbuf, 512},
		binary,
		{reuseaddr, true}]), 
	spawn(fun() ->
	accept_parallel(Listen) end),
	io:format("~p started~n", [?MODULE]),
	{ok, 0}.

accept_parallel(Listen) ->
	{ok, Socket} = gen_tcp:accept(Listen),
	spawn(fun() -> accept_parallel(Listen)	end),
	loop(Socket, <<>>).

handle_call(Request, _From, N) ->
	io:format("In handle_call we got ~p~n", [Request]),
	{reply, Request, N + 1}.

handle_cast(_Msg, N) -> 
	{noreply, N}.

handle_info(_Info, N) -> 
	{noreply, N}.	

terminate(_Reason, _N) ->
	io:format("~p stoped~n", [?MODULE]),
	ok.

code_change(_OldVsn, N, _Extra)	-> {ok, N}.


%%========== Dirty and Stinky ================%%
loop(Socket, JSON) ->
	inet:setopts(Socket, [{active, once}]),
	case jsx:is_json(JSON) of
		true ->
			An = check_data(JSON),
			gen_tcp:send(Socket, An),
			loop(Socket, <<>>);
		false -> error	
	end,	
	receive
		{tcp, Socket, Bin} ->
			case jsx:is_json(Bin) of
				true ->
					Tmp = erlang:iolist_to_binary([JSON, Bin]),
					io:format("true-~p-~n", [Tmp]),
					Answer = check_data(Tmp),
					gen_tcp:send(Socket, Answer),
					loop(Socket, <<>>);
				false ->
					Tmp = erlang:iolist_to_binary([JSON, Bin]),
					% io:format("false-~p-~n", [Tmp]),
					loop(Socket, Tmp)
			end;
		{tcp_closed, Socket} ->
			io:format("Socket ~w closed [~w]~n", [Socket, self()]),
			ok			
	end.
%%========== Dirty and Stinky ================%%	
%% TODO take a look on db_server - base64 string
check_data(Bin) ->
	case mochijson:decode(Bin) of
				{struct, [{"login", Login}, {"password", Password}]} 
				when Login =/= [], Password =/= []  ->
				 	Token = gen_server:call(security, {encode, Login, Password}),
				 	TokinizedUser = #token{login = Login, token = Token},	
					User = gen_server:call(db_server, {look_up, TokinizedUser}),
					io:format("User - ~p~n", [User]),
					User;
				{struct, [{"login", Login}, {"email", Email}, {"password", Password}]}
				when Login =/= [], Email =/= [], Password =/= [] ->
					TPassword = gen_server:call(security, {encode, Login, Password}),
					NewUser = #users{login = Login, email = Email, password = TPassword},
					gen_server:cast(db_server, {save, NewUser}),
					"ok";
				{struct, [{"image", Image}, {"question", Question}, {"user", User}]}
				when Question =/= [] ->
					QuestRecord = #quests{user = User, question = Question, data = Image},
					gen_server:cast(db_server, {save, QuestRecord}),
					"ok";
				Any ->
					io:format("Object ~p is trying to get the access~n", [Any]),
					"error"
					% "75de1aa70da3b1b24664a1b4098679c99fa1139c"	
			end.
	% {ok, Tokens, _EndLine} = erl_scan:string(Bin),
	% {ok, AbsForm} = erl_parse:parse_exprs(Tokens),	
	% io:format("~p~n", [Bin]),
	% "75de1aa70da3b1b24664a1b4098679c99fa1139c".

	

% list_length([]) -> 0;
% list_length([_|T]) -> 1 + list_length(T).
				
