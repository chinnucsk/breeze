%%====================================================================
%% Copyright (c) 2011, David Haglund
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%%     * Redistributions of source code must retain the above
%%       copyright notice, this list of conditions and the following
%%       disclaimer.
%%
%%     * Redistributions in binary form must reproduce the above
%%       copyright notice, this list of conditions and the following
%%       disclaimer in the documentation and/or other materials
%%       provided with the distribution.
%%
%%     * Neither the name of the copyright holder nor the names of its
%%       contributors may be used to endorse or promote products
%%       derived from this software without specific prior written
%%       permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
%% INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
%% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
%% HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
%% STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
%% ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
%% OF THE POSSIBILITY OF SUCH DAMAGE.
%%====================================================================

%%-------------------------------------------------------------------
%% @author David Haglund
%% @copyright 2011, David Haglund
%% @doc
%%
%% @end
%%
%% @type worker_type() = WorkerType:: epw.
%%
%% @type distribution_type() = DistributionType:: all | random | keyhash.
%%
%% @type target() = {Name::atom(), distribution_type()}.
%%
%% @type worker() = {Name::atom(), worker_type(), Callback::atom(),
%%                   NumberOfWorkers::integer(), [target()]}.
%%
%%-------------------------------------------------------------------

-module(epa_master).

-behaviour(gen_server).

%% API
-export([start_link/1]).
-export([stop/0]).

-export([get_controller/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {controller_list = []}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Config::list()) -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Config) when is_list(Config) ->
    case i_check_config_syntax(Config) of
        ok ->
            gen_server:start_link({local, ?SERVER}, ?MODULE, [Config], []);
        Error ->
            Error
    end.

stop() ->
    gen_server:call(?SERVER, stop).

get_controller(Name) when is_atom(Name) ->
    gen_server:call(?SERVER, {get_controller, Name}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Config]) ->
    Topology = proplists:get_value(topology, Config, []),
    ControllerList = i_start_topology(Topology),
    {ok, #state{controller_list = ControllerList}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call({get_controller, Name}, _From, State) ->
    Result = i_get_controller(Name, State#state.controller_list),
    {reply, Result, State};
handle_call(_Request, _From, State) ->
    {reply, error, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
i_start_topology(Topology) ->
    {ok, ControllerList} = i_start_all_epc(Topology),
    i_connect_epcs(Topology, ControllerList),
    i_start_workers(Topology, ControllerList),
    ControllerList.

i_start_all_epc(Topology) ->
    ControllerList = i_start_all_epc(Topology, _ControllerList = []),
    {ok, ControllerList}.

i_start_all_epc([{Name, WorkerType, WorkerCallback, _Children, _Targets} | Rest], Acc) ->
    WorkerMod = get_worker_mode_by_type(WorkerType),
    {ok, WorkerSup} = pc_supersup:start_worker_sup(WorkerMod, WorkerCallback),
    {ok, Controller} = epc_sup:start_epc(WorkerMod, WorkerSup),
    i_start_all_epc(Rest, [{Name, Controller} | Acc]);
i_start_all_epc([], Acc) ->
    Acc.

i_connect_epcs([{Name, _WorkerType, _Cb, _Children, Targets} | Rest], ControllerList) ->
    Pid = proplists:get_value(Name, ControllerList),
    i_connect_epcs_to_targets(Pid, Targets, ControllerList),
    i_connect_epcs(Rest, ControllerList);
i_connect_epcs([], _ControllerList) ->
    ok.

i_connect_epcs_to_targets(_Pid, _NamedTargets = [], _ControllerList) ->
    ok;
i_connect_epcs_to_targets(Pid, NamedTargets, ControllerList) ->
    Targets = lists:map(
                   fun({Name, Type}) ->
                           NamePid = proplists:get_value(Name, ControllerList),
                           {NamePid, Type}
                   end, NamedTargets),
    epc:set_targets(Pid, Targets).

i_start_workers([{Name, _WorkerType, _Cb, NumberOfWorkers, _Targets} | Rest],
		ControllerList) ->
    Pid = proplists:get_value(Name, ControllerList),
    epc:start_workers(Pid, NumberOfWorkers),
    i_start_workers(Rest, ControllerList);
i_start_workers([], _ControllerList) ->
    ok.

i_check_config_syntax(Config) ->
    Topology = proplists:get_value(topology, Config, []),
    Res = i_check_all(Topology, [fun i_check_topology_syntax/1,
                           fun i_check_topology_duplicated_names/1,
                           fun i_check_topology_target_references/1,
                           fun i_check_topology_target_reference_types/1,
                           fun i_check_topology_worker_types/1,
                           fun i_check_worker_callback_module/1
                           ]),
    Res.

i_check_all(Topology, [CheckFun | CheckFuns]) ->
    case CheckFun(Topology) of
        ok ->
            i_check_all(Topology, CheckFuns);
        Error ->
            Error
    end;
i_check_all(_Topology, []) ->
    ok.


% i_check_topology_syntax/1
i_check_topology_syntax([Worker|Rest]) when is_tuple(Worker) ->
    case i_check_worker_tuple(Worker) of
        ok ->
            i_check_topology_syntax(Rest);
        Error ->
            Error
    end;
i_check_topology_syntax([InvalidWorker|_Rest]) ->
    {error, {invalid_topology_syntax, InvalidWorker}};
i_check_topology_syntax([]) ->
    ok.

i_check_worker_tuple({Name, Type, WorkerCallback, NumWorkers, Targets}) when
      is_atom(Name) andalso
      is_atom(Type) andalso
      is_atom(WorkerCallback) andalso
      is_integer(NumWorkers) andalso
      is_list(Targets) ->
    i_check_targets(Targets);
i_check_worker_tuple(Tuple) ->
    {error, {invalid_topology_syntax, Tuple}}.

i_check_targets([{Name, Type}|Rest]) when is_atom(Name) andalso is_atom(Type) ->
    i_check_targets(Rest);
i_check_targets([InvalidTarget|_Rest]) ->
    {error, {invalid_topology_target_syntax, InvalidTarget}};
i_check_targets([]) ->
    ok.

% i_check_topology_duplicated_names/1
i_check_topology_duplicated_names(Topology) ->
   i_check_topology_duplicated_names(Topology, _ValidNames = []).

i_check_topology_duplicated_names([{Name, _, _, _, _} | Rest], ValidNames) ->
    case lists:member(Name, ValidNames) of
        true ->
            {error, duplicated_worker_name};
        _ ->
            i_check_topology_duplicated_names(Rest, [Name | ValidNames])
    end;
i_check_topology_duplicated_names([], _ValidNames) ->
    ok.

% i_check_topology_target_references/1
i_check_topology_target_references(Topology) ->
    i_check_topology_target_references(Topology, []).

i_check_topology_target_references([{Name, _, _, _, Targets} | Rest], ConsumedNames) ->
    ValidNames = ConsumedNames ++ i_extract_names(Rest),
    case i_check_target_names_is_valid(Targets, ValidNames) of
        ok ->
            i_check_topology_target_references(Rest, [Name | ConsumedNames]);
        Error ->
            Error
    end;
i_check_topology_target_references([], _) ->
    ok.

i_check_target_names_is_valid([], _ValidNames) ->
    ok;
i_check_target_names_is_valid([{TargetName, _} | Rest], ValidNames) ->
    case lists:member(TargetName, ValidNames) of
        true ->
            i_check_target_names_is_valid(Rest, ValidNames);
        _ ->
            {error, {invalid_target_ref, TargetName}}
    end.

i_extract_names(List) ->
    lists:map(fun(Worker) -> element(1, Worker) end, List).

% i_check_topology_target_reference_types/1
i_check_topology_target_reference_types([{_, _, _, _, Targets} | Rest]) ->
    case i_check_target_types(Targets) of
        ok ->
            i_check_topology_target_reference_types(Rest);
        Error ->
            Error
    end;
i_check_topology_target_reference_types([]) ->
    ok.

i_check_target_types([{_, all} |Rest]) ->
    i_check_target_types(Rest);
i_check_target_types([{_, random} | Rest]) ->
    i_check_target_types(Rest);
i_check_target_types([{_, keyhash} | Rest]) ->
    i_check_target_types(Rest);
i_check_target_types([{_, InvalidType} | _Rest]) ->
    {error, {invalid_target_ref_type, InvalidType}};
i_check_target_types([]) ->
    ok.

% i_check_topology_worker_types/1
i_check_topology_worker_types([{_, producer, _, _, _} | Rest]) ->
    i_check_topology_worker_types(Rest);
i_check_topology_worker_types([{_, consumer, _, _, _} | Rest]) ->
    i_check_topology_worker_types(Rest);
i_check_topology_worker_types([{_, InvalidWorkerType, _, _, _} | _Rest]) ->
    {error, {invalid_worker_type, InvalidWorkerType}};
i_check_topology_worker_types([]) ->
    ok.

% i_check_worker_callback_module/1
i_check_worker_callback_module([{_, WorkerType, WorkerCallback, _, _} | Rest]) ->
    WorkerMod = get_worker_mode_by_type(WorkerType),
    case WorkerMod:validate_module(WorkerCallback) of
        true ->
            i_check_worker_callback_module(Rest);
        _E ->
            {error, {invalid_worker_callback_module, WorkerCallback}}
    end;
i_check_worker_callback_module([]) ->
    ok.

% i_get_controller/2
i_get_controller(Name, ControllerList) ->
    case proplists:lookup(Name, ControllerList) of
	{Name, Pid} ->
	    {ok, Pid};
	_ ->
	    {error, {not_found, Name}}
    end.

get_worker_mode_by_type(producer) ->
    eg;
get_worker_mode_by_type(consumer) ->
    epw.
