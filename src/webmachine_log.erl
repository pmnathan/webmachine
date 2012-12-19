%% Copyright (c) 2011-2012 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

%% @doc Helper functions for webmachine's default log handlers

-module(webmachine_log).

-export([
         datehour/0,
         datehour/1,
         defer_refresh/0,
         fix_log/2,
         fmt_ip/1,
         fmtnow/0,
         log_path/2,
         log_close/1,
         log_open/2,
         log_write/2,
         maybe_rotate/2,
         month/1,
         refresh/1,
         suffix/1,
         zeropad/2,
         zone/0
        ]).

-record(state, {hourstamp, filename, handle}).

datehour() ->
    datehour(os:timestamp()).

datehour(Now) ->
    {{Y, M, D}, {H, _, _}} = calendar:now_to_universal_time(Now),
    {Y, M, D, H}.

defer_refresh() ->
    {_, {_, M, S}} = calendar:universal_time(),
    Time = 1000 * (3600 - ((M * 60) + S)),
    timer:apply_after(Time, ?MODULE, refresh, []).

%% Seek backwards to the last valid log entry
fix_log(_FD, 0) ->
    ok;
fix_log(FD, 1) ->
    {ok, 0} = file:position(FD, 0),
    ok;
fix_log(FD, Location) ->
    case file:pread(FD, Location - 1, 1) of
        {ok, [$\n | _]} ->
            ok;
        {ok, _} ->
            fix_log(FD, Location - 1)
    end.

fmt_ip(IP) when is_tuple(IP) ->
    inet_parse:ntoa(IP);
fmt_ip(undefined) ->
    "0.0.0.0";
fmt_ip(HostName) ->
    HostName.

fmtnow() ->
    {{Year, Month, Date}, {Hour, Min, Sec}} = calendar:local_time(),
    io_lib:format("[~2..0w/~s/~4..0w:~2..0w:~2..0w:~2..0w ~s]",
                  [Date,month(Month),Year, Hour, Min, Sec, zone()]).

log_close({?MODULE, Name, FD}) ->
    io:format("~p: closing log file: ~p~n", [?MODULE, Name]),
    file:close(FD).

log_open(FileName, DateHour) ->
    LogName = FileName ++ suffix(DateHour),
    io:format("opening log file: ~p~n", [LogName]),
    {ok, FD} = file:open(LogName, [read, write, raw]),
    {ok, Location} = file:position(FD, eof),
    fix_log(FD, Location),
    file:truncate(FD),
    {?MODULE, LogName, FD}.

log_path(BaseDir, FileName) ->
    filename:join(BaseDir, FileName).

log_write({?MODULE, _Name, FD}, IoData) ->
    file:write(FD, lists:flatten(IoData)).

maybe_rotate(Time, State) ->
    ThisHour = datehour(Time),
    if ThisHour == State#state.hourstamp ->
            State;
       true ->
            defer_refresh(),
            log_close(State#state.handle),
            Handle = log_open(State#state.filename, ThisHour),
            State#state{hourstamp=ThisHour, handle=Handle}
    end.

month(1) ->
    "Jan";
month(2) ->
    "Feb";
month(3) ->
    "Mar";
month(4) ->
    "Apr";
month(5) ->
    "May";
month(6) ->
    "Jun";
month(7) ->
    "Jul";
month(8) ->
    "Aug";
month(9) ->
    "Sep";
month(10) ->
    "Oct";
month(11) ->
    "Nov";
month(12) ->
    "Dec".

refresh(Time) ->
    gen_server:cast(?MODULE, {refresh, Time}).

suffix({Y, M, D, H}) ->
    YS = zeropad(Y, 4),
    MS = zeropad(M, 2),
    DS = zeropad(D, 2),
    HS = zeropad(H, 2),
    lists:flatten([$., YS, $_, MS, $_, DS, $_, HS]).

zeropad(Num, MinLength) ->
    NumStr = integer_to_list(Num),
    zeropad_str(NumStr, MinLength - length(NumStr)).

zeropad_str(NumStr, Zeros) when Zeros > 0 ->
    zeropad_str([$0 | NumStr], Zeros - 1);
zeropad_str(NumStr, _) ->
    NumStr.

zone() ->
    Time = erlang:universaltime(),
    LocalTime = calendar:universal_time_to_local_time(Time),
    DiffSecs = calendar:datetime_to_gregorian_seconds(LocalTime) -
        calendar:datetime_to_gregorian_seconds(Time),
    zone((DiffSecs/3600)*100).

%% Ugly reformatting code to get times like +0000 and -1300

zone(Val) when Val < 0 ->
    io_lib:format("-~4..0w", [trunc(abs(Val))]);
zone(Val) when Val >= 0 ->
    io_lib:format("+~4..0w", [trunc(abs(Val))]).
