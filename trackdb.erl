-module(trackdb).
-behaviour(gen_server).

-export([start/1]).

-export([snapshot/0]).
-export([all_roots/0, remove_root/1, rescan_root/1, update_root/2]).
-export([search_tracks/1]).

-export([init/1, handle_call/3]).

% Client interface

%% new_guid() ->  {node(), erlang:now()}.

start(Sconf) ->
    io:format("Starting trackdb.~n"),
    gen_server:start_link({local, trackdb}, trackdb, [], []).

snapshot() -> gen_server:call(trackdb, snapshot).
all_roots() -> gen_server:call(trackdb, all_roots).
remove_root(Url) -> gen_server:call(trackdb, {remove_root, Url}).
rescan_root(Url) -> gen_server:call(trackdb, {rescan_root, Url}).
update_root(Url, TrackUrls) -> gen_server:call(trackdb, {update_root, Url, TrackUrls}).

search_tracks(Keys) -> gen_server:call(trackdb, {search_tracks, Keys}).

% Server-side

-record(v1, {roots}).

upgrade_state(State=#v1{}) ->
    State;
upgrade_state(State) -> %% unlabeled version.
    dict:fetch_keys(State), %% ensure it's a dictionary
    upgrade_state(#v1{roots=State}).

init(_Args) ->
    case file:read_file("ejukebox.db") of
	{ok, State} -> {ok, upgrade_state(binary_to_term(State))};
	{error, enoent} -> {ok, #v1{roots = dict:new()}}
    end.

handle_call(snapshot, _From, State) ->
    {reply, file:write_file("ejukebox.db", term_to_binary(State)), State};

handle_call(all_roots, _From, State) ->
    {reply, dict:fetch_keys(State#v1.roots), State};

handle_call({remove_root, Url}, _From, State) ->
    {reply, ok, State#v1{roots = dict:erase(Url, State#v1.roots)}};

handle_call({rescan_root, Url}, _From, State) ->
    {reply, spawn(fun () -> rescanner(Url) end), State};

handle_call({update_root, Url, Q}, _From, State) ->
    {reply, ok, State#v1{roots = dict:store(Url, Q, State#v1.roots)}};

handle_call({search_tracks, Keys}, From, State) ->
    spawn(fun () -> searcher(From, Keys, State#v1.roots) end),
    {noreply, State};

handle_call({internal, extract_state}, _From, State) ->
    {reply, State, State}.

searcher(From, Keys, Roots) ->
    Matches = dict:fold(fun (_Url, Q, Acc) -> tqueue:search(Keys, Q, Acc) end, [], Roots),
    gen_server:reply(From, tqueue:finish_search(Matches)).

rescanner(Url) ->
    update_root(Url, tqueue:from_list(spider:spider(Url), null)).