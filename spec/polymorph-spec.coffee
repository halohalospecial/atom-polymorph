{Range} = require 'atom'
Polymorph = require '../lib/polymorph'

# In "annotatedBefore" and "expectedAnnotatedAfter",
# "|" represents a cursor, "[]" is an empty selection (also equal to "|"), and "[xxx]" is a selection contaning "xxx".
testMarkNextInAnyCaseAndForm = (editor, annotatedBefore, expectedAnnotatedAfter, doTimes, replacement = null) ->
  # Replace "|" with "[]" (cursor -> empty selection).
  annotatedBefore = annotatedBefore.replace '|', '[]'
  expectedAnnotatedAfter = expectedAnnotatedAfter.replace '|', '[]'

  # Get textBefore (without annotations) and rangesBefore.
  textBefore = ''
  rangesBefore = []
  row = 0
  column = 0
  for i in [0..annotatedBefore.length-1]
    ch = annotatedBefore[i]
    if ch is '['
      rangeStart = [row, column]
    else if ch is ']'
      rangeEnd = [row, column]
      rangesBefore.push new Range(rangeStart, rangeEnd)
    else if ch is '\n'
      row = row + 1
      column = 0
      textBefore = textBefore + ch
    else
      column = column + 1
      textBefore = textBefore + ch

  # The "before".
  editor.setText textBefore
  editor.setSelectedBufferRanges rangesBefore

  # Invoke polymorph:mark-next-in-any-case for each selection in "expectedAnnotatedAfter".
  editorView = atom.views.getView(editor)
  # doTimes = doTimes || expectedAnnotatedAfter.split('[').length-1
  for _ in [1..doTimes]
    atom.commands.dispatch editorView, 'polymorph:mark-next-in-any-case-and-form'

  if replacement
    editor.setTextInBufferRange rangesBefore[0], replacement
    # # Simulate user typing characters one-by-one.
    # for ch in replacement.split('')
    #   editor.insertText ch

  # Converts markers to selections. (TODO: Test with actual markers.)
  atom.commands.dispatch editorView, 'polymorph:select-all-marked'

  # Construct annotated "after" from ranges.
  textAfter = editor.getText()
  rangesAfter = editor.getSelectedBufferRanges()
  rangeIndex = 0
  range = rangesAfter[rangeIndex]
  point = range.start
  row = 0
  column = 0
  annotatedAfter = ''
  for i in [0..textAfter.length-1]
    ch = textAfter[i] || ''
    # expect('').toBe(ch + ' ' + [row, column] + JSON.stringify(point)) # # #
    if range && point.row is row && point.column is column
      if point.isEqual range.start
        annotatedAfter = annotatedAfter + '['
      if point.isEqual range.end
        annotatedAfter = annotatedAfter + ']'
      annotatedAfter = annotatedAfter + ch

      if point.isEqual range.start
        point = range.end

    else if range && point.row is row && point.column is column + 1 && point.isEqual range.end
        annotatedAfter = annotatedAfter + ch + ']'
        rangeIndex = rangeIndex + 1
        range = rangesAfter[rangeIndex]
        if range
          point = range.start
    else
      annotatedAfter = annotatedAfter + ch

    if ch is '\n'
      row = row + 1
      column = 0
    else
      column = column + 1

  expect(annotatedAfter).toBe(expectedAnnotatedAfter)

describe 'Polymorph', ->
  [editor, editorView] = []

  beforeEach ->
    waitsForPromise ->
      atom.workspace.open()

    runs ->
      editor = atom.workspace.getActiveTextEditor()

    waitsForPromise ->
      atom.packages.activatePackage('polymorph')

  afterEach ->
    Polymorph.deactivate()

  it 'should select superword when nothing is selected', ->
    testMarkNextInAnyCaseAndForm editor, '''
    |mark-next-in-any-case
    markNextInAnyCase
    ''', '''
    [mark-next-in-any-case]
    markNextInAnyCase
    ''', 1
    testMarkNextInAnyCaseAndForm editor, '''
    |polymorph:mark-next-in-any-case
    ''', '''
    [polymorph]:mark-next-in-any-case
    ''', 1
    testMarkNextInAnyCaseAndForm editor, '''
    polymorph:|mark-next-in-any-case
    ''', '''
    polymorph:[mark-next-in-any-case]
    ''', 1
    testMarkNextInAnyCaseAndForm editor, '''
    polymorph:mark-next-|in-any-case
    ''', '''
    polymorph:[mark-next-in-any-case]
    ''', 1

  it 'should not select anything if there\'s no superword', ->
    testMarkNextInAnyCaseAndForm editor, '''
    |
    ''', '''
    |
    ''', 1
    testMarkNextInAnyCaseAndForm editor, '''
    |

    ''', '''
    |

    ''', 1

  it 'should mark ranges in related letter cases', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [mark-next-in-any-case]
    markNextInAnyCase
    MarkNextInAnyCase
    mark_next_in_any_case
    MARK_NEXT_IN_ANY_CASE
    MARK-NEXT-IN-ANY-CASE
    mark-next-in-any-case
    ''', '''
    [mark-next-in-any-case]
    [markNextInAnyCase]
    [MarkNextInAnyCase]
    [mark_next_in_any_case]
    [MARK_NEXT_IN_ANY_CASE]
    [MARK-NEXT-IN-ANY-CASE]
    [mark-next-in-any-case]
    ''', 6
    testMarkNextInAnyCaseAndForm editor, '''
    export const ADD_TODO = 'ADD_TODO'
    export const [REMOVE_TODO] = 'REMOVE_TODO'

    export function addTodo(text) {
      return { type: ADD_TODO, text }
    }

    export function removeTodo(index) {
      return { type: REMOVE_TODO, index }
    }
    ''','''
    export const ADD_TODO = 'ADD_TODO'
    export const [REMOVE_TODO] = '[REMOVE_TODO]'

    export function addTodo(text) {
      return { type: ADD_TODO, text }
    }

    export function [removeTodo](index) {
      return { type: [REMOVE_TODO], index }
    }
    ''', 3

  it 'should replace shadows when source was replaced', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [mark-next-in-any-case]
    markNextInAnyCase
    MarkNextInAnyCase
    mark_next_in_any_case
    MARK_NEXT_IN_ANY_CASE
    MARK-NEXT-IN-ANY-CASE
    mark-next-in-any-case
    ''', '''
    [select-next-in-any-case]
    [selectNextInAnyCase]
    [SelectNextInAnyCase]
    [select_next_in_any_case]
    [SELECT_NEXT_IN_ANY_CASE]
    [SELECT-NEXT-IN-ANY-CASE]
    [select-next-in-any-case]
    ''', 6, 'select-next-in-any-case'

  it 'should capitalize shadow text if it\'s just one subword and source text is capitalized', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [editor] = atom.workspace.getActiveTextEditor()
    ''', '''
    [editors] = atom.workspace.getActiveText[Editors]()
    ''', 1, 'editors'

  describe 'when source and shadow are in camel or pascal case...', ->

    describe '...and source is at the beginning of a line or superword boundary', ->

      it 'should capitalize shadow if it is capitalized', ->
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase]
        MarkNextInAnyCase
        ''', '''
        [selectNextInAnyCase]
        [SelectNextInAnyCase]
        ''', 1, 'selectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase]
        markNextInAnyCase
        ''', '''
        [selectNextInAnyCase]
        [selectNextInAnyCase]
        ''', 1, 'selectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase]
        markNextInAnyCase
        ''', '''
        [SelectNextInAnyCase]
        [selectNextInAnyCase]
        ''', 1, 'SelectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase] MarkNextInAnyCase
        ''', '''
        [selectNextInAnyCase] [SelectNextInAnyCase]
        ''', 1, 'selectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase] (MarkNextInAnyCase)
        ''', '''
        [selectNextInAnyCase] ([SelectNextInAnyCase])
        ''', 1, 'selectNextInAnyCase'

    describe '...and source was capitalized', ->

      it 'should retain the capitalization of shadow if it is at the beginning of a line or superword boundary', ->
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase]
        MarkNextInAnyCase
        ''', '''
        [SelectNextInAnyCase]
        [SelectNextInAnyCase]
        ''', 1, 'SelectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase]
        markNextInAnyCase
        ''', '''
        [SelectNextInAnyCase]
        [selectNextInAnyCase]
        ''', 1, 'SelectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase] MarkNextInAnyCase
        ''', '''
        [SelectNextInAnyCase] [SelectNextInAnyCase]
        ''', 1, 'SelectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        xxx[MarkNextInAnyCase] markNextInAnyCase
        ''', '''
        xxx[SelectNextInAnyCase] [selectNextInAnyCase]
        ''', 1, 'SelectNextInAnyCase'

      it 'should change the capitalization of shadow if it is NOT at the beginning of a line or superword boundary (follow capitalization of source)', ->
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase] xxxmarkNextInAnyCasexxx
        ''', '''
        [SelectNextInAnyCase] xxx[SelectNextInAnyCase]xxx
        ''', 1, 'SelectNextInAnyCase'
        testMarkNextInAnyCaseAndForm editor, '''
        [markNextInAnyCase] xxxmarkNextInAnyCasexxx
        ''', '''
        [selectNextInAnyCase] xxx[selectNextInAnyCase]xxx
        ''', 1, 'selectNextInAnyCase'

  describe 'when source is in kebab case or snake case, and shadow is in camel case or pascal case', ->

    describe 'when source is in kebab case and source\'s first character is \'-\'', ->

      it 'should capitalize shadow', ->
        testMarkNextInAnyCaseAndForm editor, '''
        [-mark-next-in-any-case] markNextInAnyCase
        ''', '''
        [-select-next-in-any-case] [SelectNextInAnyCase]
        ''', 1, '-select-next-in-any-case'
        testMarkNextInAnyCaseAndForm editor, '''
        will-[mark-next-in-any-case] markNextInAnyCase
        ''', '''
        will-[select-next-in-any-case] [selectNextInAnyCase]
        ''', 1, 'select-next-in-any-case'
        testMarkNextInAnyCaseAndForm editor, '''
        will-[mark-next-in-any-case] xxx:markNextInAnyCase
        ''', '''
        will-[select-next-in-any-case] xxx:[selectNextInAnyCase]
        ''', 1, 'select-next-in-any-case'

    describe 'when source is in kebab case and source\'s first character is not \'-\'', ->

      it 'should retain the shadow\s capitalization', ->
        testMarkNextInAnyCaseAndForm editor, '''
        xxx-[mark-next-in-any-case]-yyy xxxMarkNextInAnyCase
        ''', '''
        xxx-[select-next-in-any-case]-yyy xxx[SelectNextInAnyCase]
        ''', 1, 'select-next-in-any-case'

    describe 'when source is in snake case and source\'s first character is \'_\'', ->

      it 'should capitalize shadow', ->
        testMarkNextInAnyCaseAndForm editor, '''
        [_mark_next_in_any_case] markNextInAnyCase
        ''', '''
        [_select_next_in_any_case] [SelectNextInAnyCase]
        ''', 1, '_select_next_in_any_case'
        testMarkNextInAnyCaseAndForm editor, '''
        will_[mark_next_in_any_case] markNextInAnyCase
        ''', '''
        will_[select_next_in_any_case] [selectNextInAnyCase]
        ''', 1, 'select_next_in_any_case'
        testMarkNextInAnyCaseAndForm editor, '''
        will_[mark_next_in_any_case] xxx:markNextInAnyCase
        ''', '''
        will_[select_next_in_any_case] xxx:[selectNextInAnyCase]
        ''', 1, 'select_next_in_any_case'

    describe 'when source is in kebab case and source\'s first character is not \'-\'', ->

      it 'should retain the shadow\s capitalization', ->
        testMarkNextInAnyCaseAndForm editor, '''
        xxx_[mark_next_in_any_case]_yyy xxxMarkNextInAnyCase
        ''', '''
        xxx_[select_next_in_any_case]_yyy xxx[SelectNextInAnyCase]
        ''', 1, 'select_next_in_any_case'

  describe 'when source is upcased, and shadow is in camel case or pascal case', ->

    it 'should follow capitalization of source (upcase, downcase, capitalized)', ->
      testMarkNextInAnyCaseAndForm editor, '''
      [ABC] withABC WithABC WithABC:start ABC abc xxxABCxxx xxxabcxxx withAbc
      ''', '''
      [XYZ] with[XYZ] With[XYZ] With[XYZ]:start [XYZ] [xyz] xxx[XYZ]xxx xxx[xyz]xxx with[XYZ]
      ''', 8, 'XYZ'

  describe 'miscellaneous tests for letter case', ->

    it 'should replace "start" with "stop"', ->
      testMarkNextInAnyCaseAndForm editor, '''
      [start]Play mediaServerStartPlay mediaServer:startPlay player:startPlay

        startPlay mediaServerStartPlay mediaServer:startPlay player:startPlay
      ''', '''
      [stop]Play mediaServer[Stop]Play mediaServer:[stop]Play player:[stop]Play

        [stop]Play mediaServer[Stop]Play mediaServer:[stop]Play player:[stop]Play
      ''', 7, 'stop'

    it 'should replace "Position" with "Point"', ->
      testMarkNextInAnyCaseAndForm editor, '''
      start[Position] {position: 0} endPosition
      ''', '''
      start[Point] {[point]: 0} end[Point]
      ''', 2, 'Point'

  #--------------------------------------------------------------------------------

  it 'should mark ranges with related inverse form', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [{(]xxx)}
    {()}
    {aaa(xxx)bbb}
    ''', '''
    [{(]xxx[)}]
    [{(][)}]
    {aaa(xxx)bbb}
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [{]aaa(xxx)bbb}
    ''', '''
    [{]aaa(xxx)bbb[}]
    ''', 1
    testMarkNextInAnyCaseAndForm editor, '''
    [<a><div>]xxx</div></a>
    <a><div></div></a>
    <a>aaa<div></div>bbb</a>
    ''', '''
    [<a><div>]xxx[</div></a>]
    [<a><div>][</div></a>]
    <a>aaa<div></div>bbb</a>
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [<div><a>]LINK</a></div>
    ''', '''
    [<span><a>]LINK[</a></span>]
    ''', 1, '<span><a>'
    testMarkNextInAnyCaseAndForm editor, '''
    [{ ]xxx }
    ''', '''
    [{ ]xxx[ }]
    ''', 1

  it 'should mark ranges with related color format', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [red]
    #f00
    #ff0000
    #ffff0000
    rgb(255, 0, 0)
    rgba(255, 0, 0, 1)
    hsv(0, 100%, 100%)
    hsl(0, 100%, 50%)
    rgb(255,0,0)
    rgba(255,0,0,1)
    hsv(0,100%,100%)
    hsl(0,100%,50%)
    ''', '''
    [red]
    [#f00]
    [#ff0000]
    [#ffff0000]
    [rgb(255, 0, 0)]
    [rgba(255, 0, 0, 1)]
    [hsv(0, 100%, 100%)]
    [hsl(0, 100%, 50%)]
    [rgb(255,0,0)]
    [rgba(255,0,0,1)]
    [hsv(0,100%,100%)]
    [hsl(0,100%,50%)]
    ''', 11

  it 'should mark ranges with related cardinality (singular, plural)', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [man] men
    ''', '''
    [woman] [women]
    ''', 1, 'woman'
    testMarkNextInAnyCaseAndForm editor, '''
    [sandwich] sandwiches
    ''', '''
    [cat] [cats]
    ''', 1, 'cat'
    testMarkNextInAnyCaseAndForm editor, '''
    [octopi] octopus
    ''', '''
    [children] [child]
    ''', 1, 'children'
    testMarkNextInAnyCaseAndForm editor, '''
    [address] addresses
    ''', '''
    [die] [dice]
    ''', 1, 'die'
    testMarkNextInAnyCaseAndForm editor, '''
    nuclear-[facility]
    nuclear-facilities
    nuclearfacilities
    NuclearFacility
    NuclearFacilities
    NUCLEAR_FACILITIES
    NUCLEAR-FACILITIES
    ''', '''
    nuclear-[building]
    nuclear-[buildings]
    nuclear[buildings]
    Nuclear[Building]
    Nuclear[Buildings]
    NUCLEAR_[BUILDINGS]
    NUCLEAR-[BUILDINGS]
    ''', 6, 'building'
    testMarkNextInAnyCaseAndForm editor, '''
    original[Cases] case originalCase getCase
    ''', '''
    original[Cases] [case] original[Case] get[Case]
    ''', 3

  it 'should mark superwords with related cardinality (singular, plural)', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [firstSelectableChild] firstSelectableChildren
    ''', '''
    [lastClickableOctopus] [lastClickableOctopi]
    ''', 1, 'lastClickableOctopus'

  it 'should mark ranges with related verb form', ->
    testMarkNextInAnyCaseAndForm editor, '''
    [dice] dices diced dicing
    ''', '''
    [dice] [dices] [diced] [dicing]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [fly] flies flew flying
    ''', '''
    [fly] [flies] [flew] [flying]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [flies] fly flew flying
    ''', '''
    [flies] [fly] [flew] [flying]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [flew] fly flies flying
    ''', '''
    [flew] [fly] [flies] [flying]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [flying] fly flies flew
    ''', '''
    [flying] [fly] [flies] [flew]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [swim] swims swam swimming
    ''', '''
    [swim] [swims] [swam] [swimming]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [run] running RUNNING Running runner RUNNER Runner
    ''', '''
    [run] [running] [RUNNING] [Running] [runner] [RUNNER] [Runner]
    ''', 6
    testMarkNextInAnyCaseAndForm editor, '''
    [walk] walking WALKING Walking walker WALKER Walker
    ''', '''
    [walk] [walking] [WALKING] [Walking] [walker] [WALKER] [Walker]
    ''', 6
    testMarkNextInAnyCaseAndForm editor, '''
    [separation] separately separation Separately SEPARATION SEPARATELY
    ''', '''
    [separation] [separately] [separation] [Separately] [SEPARATION] [SEPARATELY]
    ''', 5
    testMarkNextInAnyCaseAndForm editor, '''
    [quick] quicker quickest quickness quickly
    ''', '''
    [quick] [quicker] [quickest] [quickness] [quickly]
    ''', 4
    testMarkNextInAnyCaseAndForm editor, '''
    [do] did does done
    ''', '''
    [do] [did] [does] [done]
    ''', 3
    testMarkNextInAnyCaseAndForm editor, '''
    [undo] undid undoes undone
    ''', '''
    [undo] [undid] [undoes] [undone]
    ''', 3
