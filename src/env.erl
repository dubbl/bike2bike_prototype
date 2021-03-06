-module(env).

-import(bad, [start/1, stop/2]).

-export([start/0, stop/1, runEvent/2]).


%==============================================================================
% Macros
%==============================================================================

-define(NUM_BAD, 5).        % Number of BAD processes
-define(MAX_DIST, 20).      % Maximum Range for Inter BAD Communication in Meters



%==============================================================================
% Start API function to start the Environment and the BADs.
%==============================================================================

start() ->
    ENVID = spawn(fun() -> init() end),
    io:format("ENV: Started with PID: ~p~n", [ENVID]),
    BADList = testcase(ENVID, tc0()),
    % Send accident signal after 12s (enough time to get acquainted with all BADs)
    % -- not part of this prototype (limited due to time/cost restrictions)
    % {ChosenBAD, _} = lists:nth(2, BADList),
    % timer:apply_after(12000, env, runEvent, [ChosenBAD, accident]),
    ENVID ! {badlist, BADList},
    {ENVID, BADList}.



%==============================================================================
% Helper to receive the list of BADs *after* the Environment has been created.
%==============================================================================

init() ->
    receive
        {badlist, BADList} ->
            io:format("ENV: Received BAD List with ~p BAD IDs.~n", [length(BADList)]),
            loop(BADList, dict:new())
    end.



%==============================================================================
% Recursive Helper to start a number of BADs.
%==============================================================================

startBADs(0, _) -> [];
startBADs(N, ENVID) when N > 0 ->
    {BADID, PingTimer} = bad:start(ENVID),
    io:format("ENV: Started BAD with ID: ~p~n", [BADID]),
    [{BADID, PingTimer}] ++ startBADs(N-1, ENVID).



%==============================================================================
% Stop API function to stop the Environment and the BADs.
%==============================================================================

stop(ENVID) -> ENVID ! {stop}.



%==============================================================================
% Main loop of the Environment, receiving BAD pings and Stop signal.
%==============================================================================

loop(BADList, BADLoc) ->
    receive
        {From, {ping, {Lat, Long}}} ->
            io:format("ENV: Received Ping from BAD ~p~n", [From]),
            lists:foreach(fun({BADID, _}) ->
                case dict:is_key(From, BADLoc) of
                    true ->
                        {LatNext, LongNext} = dict:fetch(BADID, BADLoc),
                        Dist = distance(Lat, Long, LatNext, LongNext),
                        case Dist < ?MAX_DIST of
                            true ->             % BAD in range
                                io:format("ENV: BAD ~p in range of ~p (~pm)!~n", [BADID, From, Dist]),
                                BADID ! {From, {ping, {Lat, Long}}};
                            false ->            % BAD not in range
                                io:format("ENV: BAD ~p *not* in range of ~p (~pm)!~n", [BADID, From, Dist])
                        end;
                    false ->
                        donothing % Update happens below
                end
                end, BADList),
            NewBADLoc = dict:update(From, fun(_) -> {Lat, Long} end, {Lat, Long}, BADLoc),
            loop(BADList, NewBADLoc);
        {stop} ->
            io:format("ENV: Received Stop signal~n"),
            lists:foreach(fun({BADID, PingTimer}) ->
                bad:stop(BADID, PingTimer)
                end, BADList)
    end.



%==============================================================================
% Function to calculate the disance between two geographical coordinates.
%==============================================================================

distance(LatA, LongA, LatB, LongB) ->
    R = 6378.137,                               % Radius of earth in KM
    DLat = (LatB - LatA) * math:pi() / 180,
    DLong = (LongB - LongA) * math:pi() / 180,
    A = math:sin(DLat/2) * math:sin(DLat/2) + math:cos(LatA * math:pi() / 180) * math:cos(LatB * math:pi() / 180) * math:sin(DLong/2) * math:sin(DLong/2),
    C = 2 * math:atan2(math:sqrt(A), math:sqrt(1-A)),
    D = R * C,
    D * 1000.                                    % Distance in Meters



%==============================================================================
% Fuction to Create Event in a BAD
%==============================================================================
runEvent(BADID, EventType) ->
    BADID ! {event, EventType}.



%==============================================================================
% Fuction to Run Test Case
%==============================================================================

testcase(ENVID, CoordList) ->
    % start BADs and get their PIDs in a list
    Indices = lists:seq(1, length(CoordList)),
    BADList = startBADs(length(CoordList), ENVID),
    lists:foreach(fun(Index) ->
        {BADID, _} = lists:nth(Index, BADList),
        Coord = lists:nth(Index, CoordList),
        io:format("ENV: Started BAD ~p with Coords ~p.~n", [BADID, Coord]),
        BADID ! {setloc, Coord}
    end, Indices),
    BADList.



%==============================================================================
% CoordList for TestCase0
%==============================================================================

tc0() ->
    [
        {55.702511, 12.562537},
        {55.702497, 12.562658},
        {55.702499, 12.562778},
        {55.702521, 12.562599},
        {55.702462, 12.562092}  % out of range for everyone else
    ].


