%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_auth_redis_SUITE).

-compile(export_all).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("common_test/include/ct.hrl").

-include("emq_auth_redis.hrl").

-define(INIT_ACL, [{"mqtt_acl:test1", "topic1", "2"},
                   {"mqtt_acl:test2", "topic2", "1"},
                   {"mqtt_acl:test3", "topic3", "3"}]).

-define(INIT_AUTH, [{"mqtt_user:root", ["password", "3ef26c7a285bbfdebd8ebe895dbada207d926c15", "salt", "salt", "is_superuser", "1"]},
                    {"mqtt_user:user1", ["password", "b95de58f7646da3b2de64466b3429244885addac", "salt", "salt", "is_superuser", "0"]}]).

all() -> 
    [{group, emq_auth_redis}].

groups() -> 
    [{emq_auth_redis, [sequence],
     [check_auth,
      check_acl]}].

init_per_suite(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    application:start(lager),
    [start_apps(App, DataDir) || App <- [emqttd, emq_auth_redis]],
    {ok, Connection} = ecpool_worker:client(gproc_pool:pick_worker({ecpool, emq_auth_redis})), [{connection, Connection} | Config].

end_per_suite(_Config) ->
    application:stop(emq_auth_redis),
    application:stop(ecpool),
    application:stop(eredis),
    application:stop(emqttd),
    emqttd_mnesia:ensure_stopped().

check_acl(Config) ->
    Connection = proplists:get_value(connection, Config),
    Keys = [Key || {Key, _Value} <- ?INIT_ACL],
    [eredis:q(Connection, ["HSET", Key, Filed, Value]) || {Key, Filed, Value} <- ?INIT_ACL],
    User1 = #mqtt_client{client_id = <<"client1">>, username = <<"test1">>},
    User2 = #mqtt_client{client_id = <<"client2">>, username = <<"test2">>},
    User3 = #mqtt_client{client_id = <<"client3">>, username = <<"test3">>},
    User4 = #mqtt_client{client_id = <<"client4">>, username = <<"$$user4">>},
    deny = emqttd_access_control:check_acl(User1, subscribe, <<"topic1">>),
    allow = emqttd_access_control:check_acl(User1, publish, <<"topic1">>),

    deny = emqttd_access_control:check_acl(User2, publish, <<"topic2">>),
    allow = emqttd_access_control:check_acl(User2, subscribe, <<"topic2">>),
    
    allow = emqttd_access_control:check_acl(User3, publish, <<"topic3">>),
    allow = emqttd_access_control:check_acl(User3, subscribe, <<"topic3">>),
    
    allow = emqttd_access_control:check_acl(User4, publish, <<"a/b/c">>),
    eredis:q(Connection, ["DEL" | Keys]).

check_auth(Config) ->
    Connection = proplists:get_value(connection, Config),
    Keys = [Key || {Key, _Filed, _Value} <- ?INIT_AUTH],
    [eredis:q(Connection, ["HMSET", Key|FiledValue]) || {Key, FiledValue} <- ?INIT_AUTH],
    User1 = #mqtt_client{client_id = <<"client1">>, username = <<"user1">>},
    User2 = #mqtt_client{client_id = <<"client2">>, username = <<"root">>},
    User3 = #mqtt_client{client_id = <<"client3">>},
    {ok, false} = emqttd_access_control:auth(User1, <<"test">>),
    {error, _} = emqttd_access_control:auth(User1, <<"pwderror">>),

    {ok, true} = emqttd_access_control:auth(User2, <<"test1">>),
    {error, _} = emqttd_access_control:auth(User2, <<"pass">>),
    {error, _} = emqttd_access_control:auth(User2, <<>>),
    {error, username_or_password_undefined} = emqttd_access_control:auth(User3, <<>>),
    eredis:q(Connection, ["DEL" | Keys]).

start_apps(App, DataDir) ->
    Schema = cuttlefish_schema:files([filename:join([DataDir, atom_to_list(App) ++ ".schema"])]),
    Conf = conf_parse:file(filename:join([DataDir, atom_to_list(App) ++ ".conf"])),
    NewConfig = cuttlefish_generator:map(Schema, Conf),
    Vals = proplists:get_value(App, NewConfig),
    [application:set_env(App, Par, Value) || {Par, Value} <- Vals],
    application:ensure_all_started(App).

