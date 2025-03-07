%%--------------------------------------------------------------------
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2008-2023. All Rights Reserved.
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
%%
%% %CopyrightEnd%
%%----------------------------------------------------------------------
%% File    : xmerl_sax_parser.erl
%% Description : XML SAX parse API module.
%%
%% Created :  4 Jun 2008
%%----------------------------------------------------------------------
-module(xmerl_sax_parser).

%%----------------------------------------------------------------------
%% Include files
%%----------------------------------------------------------------------
-include("xmerl_sax_parser.hrl").

%%----------------------------------------------------------------------
%% External exports
%%----------------------------------------------------------------------
-export([file/2,
	 stream/3,
	 stream/2]).

%%----------------------------------------------------------------------
%% Internal exports
%%----------------------------------------------------------------------
-export([default_continuation_cb/1]).

%%----------------------------------------------------------------------
%% Types
%%----------------------------------------------------------------------
-type options() :: [{continuation_fun, continuation_fun()} |
                    {continuation_state, continuation_state()} |
                    {event_fun, event_fun()} |
                    {event_state, event_state()} |
                    {file_type, normal | dtd} |
                    {encoding, utf | {utf16, big} | {utf16,little} | latin1 | list } |
                    skip_external_dtd | disallow_entities |
                    {entity_recurse_limit, non_neg_integer()} |
                    {external_entities, all | file | none} |
                    {fail_undeclared_ref, boolean()}].
-type continuation_state() :: term().
-type continuation_fun() :: fun((continuation_state()) ->
                                       {NewBytes :: binary() | list(),
                                        continuation_state()}).
-type event_state() :: term().
-type event_fun() :: fun((event(), event_location(), event_state()) -> event_state()).
-type event_location() :: {CurrentLocation :: string(),
                           Entityname :: string(),
                           LineNo :: integer()}.
-type event() :: startDocument | endDocument |
                 {startPrefixMapping, Prefix :: string(), Uri :: string()} |
                 {endPrefixMapping, Prefix :: string()} |
                 {startElement, Uri :: string(), LocalName :: string(),
                  QualifiedName :: string(), Attributes :: string()} |
                 {endElement, Uri :: string(), LocalName :: string(), QualifiedName :: string()} |
                 {characters, string()} |
                 {ignorableWhitespace, string()} |
                 {processingInstruction, Target :: string(), Data :: string()} |
                 {comment, string()} |
                 startCDATA |
                 endCDATA |
                 {startDTD, Name :: string(), PublicId :: string(), SystemId :: string()} |
                 endDTD |
                 {startEntity, SysId :: string()} |
                 {endEntity, SysId :: string()} |
                 {elementDecl, Name :: string(), Model :: string()} |
                 {attributeDecl, ElementName :: string(), AttributeName :: string(),
                  Type :: string(), Mode :: string(), Value :: string()} |
                 {internalEntityDecl, Name :: string(), Value :: string()} |
                 {externalEntityDecl, Name :: string(), PublicId :: string(), SystemId :: string()} |
                 {unparsedEntityDecl, Name :: string(), PublicId :: string(), SystemId :: string(), Ndata :: string()} |
                 {notationDecl, Name :: string(), PublicId :: string(), SystemId :: string()}.

-type unicode_char() :: char().
-type unicode_binary() :: binary().
-type latin1_binary() :: unicode:latin1_binary().

-export_type([options/0, unicode_char/0, unicode_binary/0, latin1_binary/0]).

%%----------------------------------------------------------------------
%% Macros
%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Records
%%----------------------------------------------------------------------

%%======================================================================
%% External functions
%%======================================================================
%%----------------------------------------------------------------------
%% Function: file(Filename, Options) -> Result
%% Input:    Filename = string()
%%           Options = [{OptTag, term()}]
%%           OptTag = event_state | event_fun | continuation_state |
%%                    continuation_fun | ....
%% Output:   Result = {ok, EventState, Rest}
%%           Rest = unicode_binary() | latin1_binary()
%%           EventState = term()
%% Description: Parse file containing an XML document.
%%----------------------------------------------------------------------
-spec file(Name, Options) -> {ok, EventState, Rest} | ErrorOrUserReturn when
      Name :: file:filename(),
      Options :: options(),
      EventState :: event_state(),
      Rest :: unicode_binary() | latin1_binary(),
      ErrorOrUserReturn :: {Tag, Location, Reason, EndTags, EventState},
      Tag :: fatal_error | atom(),
      Location :: event_location(),
      Reason :: term(),
      EndTags :: term().
file(Name,Options) ->
    case file:open(Name, [raw, read_ahead, read,binary])  of
        {error, Reason} ->
            {error,{Name, file:format_error(Reason)}};
        {ok, FD} ->
	    Dir = filename:dirname(Name),
	    CL = filename:absname(Dir),
            File = filename:basename(Name),
	    ContinuationFun = fun default_continuation_cb/1,
            Res = stream(<<>>,
                         [{continuation_fun, ContinuationFun},
                          {continuation_state, FD},
                          {current_location, CL},
                          {entity, File}
                          |Options],
                         file),
	    ok = file:close(FD),
	    Res
    end.

%%----------------------------------------------------------------------
%% Function: stream(Xml, Options) -> Result
%% Input:    Xml = string() | binary()
%%           Options = [{OptTag, term()}]
%%           OptTag = event_state | event_fun | continuation_state |
%%                    continuation_fun | ....
%% Output:   Result = {ok, EventState, Rest}
%%           Rest = unicode_binary() | latin1_binary() | [unicode_char()]
%%           EventState = term()
%% Description: Parse a stream containing an XML document.
%%----------------------------------------------------------------------
-spec stream(Xml, Options) -> {ok, EventState, Rest} | ErrorOrUserReturn when
      Xml :: unicode_binary() | latin1_binary() | [unicode_char],
      Options :: options(),
      EventState :: event_state(),
      Rest :: unicode_binary() | latin1_binary(),
      ErrorOrUserReturn :: {Tag, Location, Reason, EndTags, EventState},
      Tag :: fatal_error | atom(),
      Location :: event_location(),
      Reason :: term(),
      EndTags :: term().
stream(Xml, Options) ->
    stream(Xml, Options, stream).

stream(Xml, Options, InputType) when is_list(Xml), is_list(Options) ->
    State = parse_options(Options, initial_state()),
    case State#xmerl_sax_parser_state.file_type of
	dtd ->
	    xmerl_sax_parser_list:parse_dtd(Xml,
					    State#xmerl_sax_parser_state{encoding = list,
									 input_type = InputType});
	normal ->
	    xmerl_sax_parser_list:parse(Xml,
					State#xmerl_sax_parser_state{encoding = list,
								     input_type = InputType})
    end;
stream(Xml, Options, InputType) when is_binary(Xml), is_list(Options) ->
    case parse_options(Options, initial_state()) of
	{error, Reason} -> {error, Reason};
	State ->
	    ParseFunction =
		case  State#xmerl_sax_parser_state.file_type of
		    dtd ->
			parse_dtd;
		    normal ->
			parse
		end,
                try
                    {Xml1, State1} = detect_charset(Xml, State),
                     parse_binary(Xml1,
                                  State1#xmerl_sax_parser_state{input_type = InputType},
                                  ParseFunction)
                catch
                    throw:{fatal_error, {State2, Reason}} ->
                      {fatal_error,
                       {
                         State2#xmerl_sax_parser_state.current_location,
                         State2#xmerl_sax_parser_state.entity,
                         1
                        },
                       Reason, [],
                       State2#xmerl_sax_parser_state.event_state}
              end
    end.

%%----------------------------------------------------------------------
%% Function: parse_binary(Encoding, Xml, State, F) -> Result
%% Input:    Encoding = atom()
%%           Xml = [integer()] | binary()
%%           State = #xmerl_sax_parser_state
%%           F = atom()
%% Output:   Result = {ok, Rest, EventState}
%%           Rest = list() | binary()
%%           EventState = term()
%% Description: Chooses the correct parser depending on the encoding.
%%----------------------------------------------------------------------
parse_binary(Xml, #xmerl_sax_parser_state{encoding=utf8}=State, F) ->
    xmerl_sax_parser_utf8:F(Xml, State);
parse_binary(Xml, #xmerl_sax_parser_state{encoding={utf16,little}}=State, F) ->
    xmerl_sax_parser_utf16le:F(Xml, State);
parse_binary(Xml, #xmerl_sax_parser_state{encoding={utf16,big}}=State, F) ->
    xmerl_sax_parser_utf16be:F(Xml, State);
parse_binary(Xml, #xmerl_sax_parser_state{encoding=latin1}=State, F) ->
    xmerl_sax_parser_latin1:F(Xml, State);
parse_binary(_, #xmerl_sax_parser_state{encoding=Enc}, State) ->
    ?fatal_error(State, lists:flatten(io_lib:format("Character set ~p not supported", [Enc]))).

%%----------------------------------------------------------------------
%% Function: initial_state/0
%% Input:    -
%% Output:   #xmerl_sax_parser_state{}
%% Description: Creates the initial state record.
%%----------------------------------------------------------------------
initial_state() ->
    #xmerl_sax_parser_state{
	       event_fun = fun default_event_cb/3,
	       ns = [{"xml", "http://www.w3.org/XML/1998/namespace"}],
	       current_location = ".",
	       entity = ""
	      }.

%%----------------------------------------------------------------------
%% Function: parse_options(Options, State)
%% Input:    Options = [Option]
%%           Option = {event_state, term()} | {event_fun, fun()} |
%%                    {continuation_state, term()} | {continuation_fun, fun()} |
%%                    {encoding, Encoding} | {file_type, FT}
%%           FT = normal | dtd
%%           Encoding = utf8 | utf16le | utf16be | list | iso8859
%%           State = #xmerl_sax_parser_state{}
%% Output:   #xmerl_sax_parser_state{}
%% Description: Checks the parser options.
%%----------------------------------------------------------------------
parse_options([], State) ->
    State;
parse_options([{event_state, CbState} |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{event_state = CbState});
parse_options([{event_fun, CbF} |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{event_fun = CbF});
parse_options([{continuation_state, CState} |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{continuation_state = CState});
parse_options([{continuation_fun, CF} |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{continuation_fun = CF});
parse_options([{file_type, FT} |Options], State) when FT==normal; FT==dtd ->
    parse_options(Options, State#xmerl_sax_parser_state{file_type = FT});
parse_options([{encoding, E} |Options], State) ->
    case check_encoding_option(E) of
	{error, Reason} ->
	    {error, Reason};
	Enc ->
	    parse_options(Options, State#xmerl_sax_parser_state{encoding = Enc})
    end;
parse_options([{current_location, CL} |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{current_location = CL});
parse_options([{entity, Entity} |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{entity = Entity});
parse_options([skip_external_dtd |Options], State) ->
    %% Skip external DTD also sets fail_undeclared_ref to false to be compatible
    parse_options(Options, State#xmerl_sax_parser_state{skip_external_dtd = true,
                                                        fail_undeclared_ref = false});
parse_options([disallow_entities |Options], State) ->
    parse_options(Options, State#xmerl_sax_parser_state{allow_entities = false});
parse_options([{entity_recurse_limit, N} |Options], State) when is_integer(N) ->
    parse_options(Options, State#xmerl_sax_parser_state{entity_recurse_limit = N});
parse_options([{external_entities, Type} |Options], State) when Type =:= all;
                                                                Type =:= file;
                                                                Type =:= none ->
    parse_options(Options, State#xmerl_sax_parser_state{external_entities = Type});
parse_options([{fail_undeclared_ref, Bool} |Options], State) when is_boolean(Bool) ->
    parse_options(Options, State#xmerl_sax_parser_state{fail_undeclared_ref = Bool});
parse_options([O |_], _State) ->
     {error, lists:flatten(io_lib:format("Option: ~p not supported", [O]))}.


check_encoding_option(E) when E==utf8; E=={utf16,little}; E=={utf16,big};
			      E==latin1; E==list ->
    E;
check_encoding_option(utf16) ->
    {utf16,big};
check_encoding_option(E) ->
    {error, io_lib:format("Character set ~p not supported", [E])}.

%%----------------------------------------------------------------------
%% Function: detect_charset(Xml, State)
%% Input:  Xml = list() | binary()
%%         State = #xmerl_sax_parser_state{}
%% Output:  {utf8|utf16le|utf16be|iso8859, Xml, State}
%% Description: Detects which character set is used in a binary stream.
%%----------------------------------------------------------------------
detect_charset(<<>>, #xmerl_sax_parser_state{continuation_fun = undefined} = State) ->
    ?fatal_error(State, "Can't detect character encoding due to lack of indata");
detect_charset(<<>>, State) ->
    cf(<<>>, State, fun detect_charset/2);
detect_charset(Bytes, State) ->
    case unicode:bom_to_encoding(Bytes) of
	{latin1, 0} ->
	    detect_charset_1(Bytes, State);
	{Enc, Length} ->
	    <<_:Length/binary, RealBytes/binary>> = Bytes,
	    {RealBytes, State#xmerl_sax_parser_state{encoding=Enc}}
    end.

detect_charset_1(<<16#00>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#00, 16#3C>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#00, 16#3C, 16#00>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#00, 16#3C, 16#00, 16#3F, _/binary>> = Xml, State) ->
    {Xml, State#xmerl_sax_parser_state{encoding={utf16, big}}};
detect_charset_1(<<16#3C>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#00>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#00, 16#3F>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#00, 16#3F, 16#00, _/binary>> = Xml, State) ->
    {Xml, State#xmerl_sax_parser_state{encoding={utf16, little}}};
detect_charset_1(<<16#3C>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#3F>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#3F, 16#78>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#3F, 16#78, 16#6D>> = Xml, State) ->
    cf(Xml, State, fun detect_charset_1/2);
detect_charset_1(<<16#3C, 16#3F, 16#78, 16#6D, 16#6C, Xml2/binary>>, State) ->
    {Xml3, State1} = read_until_end_of_xml_directive(Xml2, State),
    AttrList = parse_xml_directive(Xml3, State),
    case lists:keysearch("encoding", 1, AttrList) of
        {value, {_, E}} ->
            Enc = convert_encoding(E, State),
            {<<16#3C, 16#3F, 16#78, 16#6D, 16#6C, Xml3/binary>>,
             State1#xmerl_sax_parser_state{encoding=Enc}};
        _ ->
            {<<16#3C, 16#3F, 16#78, 16#6D, 16#6C, Xml3/binary>>, State1}
    end;
detect_charset_1(Xml, State) ->
    {Xml, State}.

%%----------------------------------------------------------------------
%% Function: convert_encoding(Enc)
%% Input:  Enc = string()
%% Output:  utf8 | iso8859
%% Description: Converting 7,8 bit and utf8 encoding strings to internal format.
%%----------------------------------------------------------------------
convert_encoding(Enc, State) -> %% Just for 7,8 bit + utf8
    case string:to_lower(Enc) of
	"utf-8" -> utf8;
	"us-ascii" -> utf8;
	"latin1" -> latin1;
	"iso-8859-1" -> latin1; % Handle all iso-8859 as latin1
	"iso-8859-2" -> latin1;
	"iso-8859-3" -> latin1;
	"iso-8859-4" -> latin1;
	"iso-8859-5" -> latin1;
	"iso-8859-6" -> latin1;
	"iso-8859-7" -> latin1;
	"iso-8859-8" -> latin1;
	"iso-8859-9" -> latin1;
	_ -> ?fatal_error(State, "Unknown encoding: " ++ Enc)
    end.

%%----------------------------------------------------------------------
%% Function: parse_xml_directive(Xml)
%% Input:  Xml = binary()
%%         Acc = list()
%% Output:
%% Description: Parsing the xml declaration from the input stream.
%%----------------------------------------------------------------------
parse_xml_directive(<<C, Rest/binary>>, State) when ?is_whitespace(C) ->
   parse_xml_directive_1(Rest, [], State);
parse_xml_directive(_, State) ->
    ?fatal_error(State, "Expected whitespace in directive").


%%----------------------------------------------------------------------
%% Function: parse_xml_directive_1(Xml, Acc) -> [{Name, Value}]
%% Input:  Xml = binary()
%%         Acc = [{Name, Value}]
%%         Name = string()
%%         Value = string()
%% Output: see above
%% Description: Parsing the xml declaration from the input stream.
%%----------------------------------------------------------------------
parse_xml_directive_1(<<C, Rest/binary>>, Acc, State) when ?is_whitespace(C) ->
    parse_xml_directive_1(Rest, Acc, State);
parse_xml_directive_1(<<"?>", _/binary>>, Acc, _State) ->
    Acc;
parse_xml_directive_1(<<C, Rest/binary>>, Acc, State) when 97 =< C, C =< 122 ->
    {Name, Rest1} = parse_name(Rest, [C]),
    Rest2 = parse_eq(Rest1, State),
    {Value, Rest3} = parse_value(Rest2, State),
    parse_xml_directive_1(Rest3, [{Name, Value} |Acc], State);
parse_xml_directive_1(_, _, State) ->
    ?fatal_error(State, "Unknown attribute in xml directive").

%%----------------------------------------------------------------------
%% Function: parse_name(Xml, Acc) -> Name
%% Input:   Xml = binary()
%%          Acc = string()
%% Output:  Name = string()
%% Description: Parsing an attribute name from the stream.
%%----------------------------------------------------------------------
parse_name(<<C, Rest/binary>>, Acc) when 97 =< C, C =< 122 ->
    parse_name(Rest, [C |Acc]);
parse_name(Rest, Acc) ->
    {lists:reverse(Acc), Rest}.

%%----------------------------------------------------------------------
%% Function: parse_eq(Xml) -> Rest
%% Input:  Xml = binary()
%% Output:  Rest = binary()
%% Description: Reads an '=' from the stream.
%%----------------------------------------------------------------------
parse_eq(<<C, Rest/binary>>, State) when ?is_whitespace(C) ->
    parse_eq(Rest, State);
parse_eq(<<"=", Rest/binary>>, _State) ->
    Rest;
parse_eq(_, State) ->
    ?fatal_error(State, "expecting = or whitespace").

%%----------------------------------------------------------------------
%% Function: parse_value(Xml) -> {Value, Rest}
%% Input:   Xml = binary()
%% Output:  Value = string()
%%          Rest = binary()
%% Description: Parsing an attribute value from the stream.
%%----------------------------------------------------------------------
parse_value(<<C, Rest/binary>>, State) when ?is_whitespace(C) ->
    parse_value(Rest, State);
parse_value(<<C, Rest/binary>>, State) when C == $'; C == $" ->
    parse_value_1(Rest, C, [], State);
parse_value(_, State) ->
    ?fatal_error(State, "\', \" or whitespace expected").

%%----------------------------------------------------------------------
%% Function: parse_value_1(Xml, Stop, Acc) -> {Value, Rest}
%% Input:   Xml = binary()
%%          Stop = $' | $"
%%          Acc = list()
%% Output:  Value = string()
%%          Rest = binary()
%% Description: Parsing an attribute value from the stream.
%%----------------------------------------------------------------------
parse_value_1(<<Stop, Rest/binary>>, Stop, Acc, _State) ->
    {lists:reverse(Acc), Rest};
parse_value_1(<<C, Rest/binary>>, Stop, Acc, State) ->
    parse_value_1(Rest, Stop, [C |Acc], State);
parse_value_1(_, _Stop, _Acc, State) ->
    ?fatal_error(State, "end of input and no \' or \" found").

%%======================================================================
%% Default functions
%%======================================================================
%%----------------------------------------------------------------------
%% Function: default_event_cb(Event, LineNo, State) -> Result
%% Input:   Event = tuple()
%%          LineNo = integer()
%%          State = term()
%% Output:  Result = {ok, State}
%% Description: Default event callback printing event.
%%----------------------------------------------------------------------
default_event_cb(_Event, _LineNo, State) ->
    State.

%%----------------------------------------------------------------------
%% Function: default_continuation_cb(IoDevice) -> Result
%%          IoDevice = iodevice()
%% Output:  Result = {binary(), IoDevice}
%% Description: Default continuation callback reading blocks.
%%----------------------------------------------------------------------
default_continuation_cb(IoDevice) ->
    case file:read(IoDevice, 1024) of
	eof ->
	    {<<>>, IoDevice};
	{ok, FileBin} ->
	    {FileBin, IoDevice}
    end.

%%----------------------------------------------------------------------
%% Function: read_until_end_of_xml_directive(Rest, State) -> Result
%%          Rest = binary()
%% Output:  Result = {binary(), State}
%% Description: Reads a utf8 or latin1 until it finds '?>'
%%----------------------------------------------------------------------
read_until_end_of_xml_directive(Rest, State) ->
    case binary:match(Rest, <<"?>">>) of
        nomatch ->
            case cf(Rest, State) of
                {<<>>, _} ->
                    ?fatal_error(State, "Can't detect character encoding due to lack of indata");
                {NewBytes, NewState} ->
                    read_until_end_of_xml_directive(NewBytes, NewState)
            end;
        _ ->
            {Rest, State}
    end.


%%----------------------------------------------------------------------
%% Function  : cf(Rest, State) -> Result
%% Parameters: Rest = binary()
%%             State = #xmerl_sax_parser_state{}
%%             NextCall = fun()
%% Result    : {Rest, State}
%% Description: Function that uses provided fun to read another chunk from
%%              input stream and calls the fun in NextCall.
%%----------------------------------------------------------------------
cf(_Rest, #xmerl_sax_parser_state{continuation_fun = undefined} = State) ->
    ?fatal_error(State, "Continuation function undefined");
cf(Rest, #xmerl_sax_parser_state{continuation_fun = CFun, continuation_state = CState} = State) ->
    Result =
	try
	    CFun(CState)
	catch
	    throw:ErrorTerm ->
		?fatal_error(State, ErrorTerm);
            exit:Reason ->
		?fatal_error(State, {'EXIT', Reason})
	end,
    case Result of
	{<<>>, _} ->
	    ?fatal_error(State, "Can't detect character encoding due to lack of indata");
	{NewBytes, NewContState} ->
            {<<Rest/binary, NewBytes/binary>>,
             State#xmerl_sax_parser_state{continuation_state = NewContState}}
    end.

%%----------------------------------------------------------------------
%% Function  : cf(Rest, State, NextCall) -> Result
%% Parameters: Rest = binary()
%%             State = #xmerl_sax_parser_state{}
%%             NextCall = fun()
%% Result    : {Rest, State}
%% Description: Function that uses provided fun to read another chunk from
%%              input stream and calls the fun in NextCall.
%%----------------------------------------------------------------------
cf(_Rest, #xmerl_sax_parser_state{continuation_fun = undefined} = State, _) ->
    ?fatal_error(State, "Continuation function undefined");
cf(Rest, #xmerl_sax_parser_state{continuation_fun = CFun, continuation_state = CState} = State,
   NextCall) ->
    Result =
	try
	    CFun(CState)
	catch
	    throw:ErrorTerm ->
		?fatal_error(State, ErrorTerm);
            exit:Reason ->
		?fatal_error(State, {'EXIT', Reason})
	end,
    case Result of
	{<<>>, _} ->
	    ?fatal_error(State, "Can't detect character encoding due to lack of indata");
	{NewBytes, NewContState} ->
	    NextCall(<<Rest/binary, NewBytes/binary>>,
		     State#xmerl_sax_parser_state{continuation_state = NewContState})
    end.
