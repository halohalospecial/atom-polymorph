{CompositeDisposable, Point, Range} = require 'atom'
nlp = require 'nlp_compromise'
tinycolor = require 'tinycolor2'

module.exports = Polymorph =
  activate: (state) ->
    @markers = []
    # A "shadow" text is source text in a different letter case or form.
    # For example, "markNextInAny" is a shadow of "mark-next-in-any" source text. "mark-next-in-any" is also a shadow of "mark-next-in-any".
    # "octopi" is a shadow of "octopus" (different cardinality).
    @shadows = {}
    @sourcePosition = null
    @sourceScroll = null
    @lastShadowMatchRange = null
    @editing = false

    allForms = {case: true, inverse: true, cardinality: true, verbForm: true, adjectiveForm: true, colorFormat: true}

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-text-editor',
      'polymorph:mark-next-in-any-case-and-form': => @markNextInAny allForms
      'polymorph:mark-next-in-any-case': => @markNextInAny {case: true}
      'polymorph:mark-next-in-any-inverse': => @markNextInAny {inverse: true}
      'polymorph:mark-next-in-any-cardinality': => @markNextInAny {cardinality: true}
      'polymorph:mark-next-in-any-verb-form': => @markNextInAny {verbForm: true}
      'polymorph:mark-next-in-any-adjective-form': => @markNextInAny {adjectiveForm: true}
      'polymorph:mark-next-in-any-color-format': => @markNextInAny {colorFormat: true}

      'polymorph:skip-last-marked': => @skipLastMarked()
      'polymorph:select-all-marked': => @selectAllMarked()
      'polymorph:case-preserving-paste': => @casePreservingPaste()

      'core:cancel':  => @stopEditing() if @editing
      # 'blur':  => @stopEditing() if @editing

  deactivate: ->
    @stopEditing()
    @subscriptions.dispose()

  serialize: ->

  stopEditing: ->
    @editor.groupChangesSinceCheckpoint(@checkpoint) if @checkpoint?
    @sourceMarkerOnDidChangeDisposable?.dispose()
    marker.destroy() for marker in @markers
    @markers = []
    @shadows = {}
    @sourcePosition = null
    if @sourceScroll?
      editorView = atom.views.getView @editor
      editorView.setScrollLeft @sourceScroll.left
      editorView.setScrollTop @sourceScroll.top
    @sourceScroll = null
    @lastShadowMatchRange = null
    @editing = false

  # Marks the next range of text that has a related form to the text of the last selection.
  # Example: If the selected text is "markNextInAny", it will match "mark-next-in-any" (kebab cased form) and "mark_next_in_any" (snake cased form).
  # Example: If the selected text is "mark", it will match "marks" (pluralized form).
  # Example: If the selected text is "marks", it will match "mark" (singularized form).
  # Example: If the selected text is "marks", it will match "marks" (itself).
  markNextInAny: (includedForms={case: true}) ->
    editor = atom.workspace.getActiveTextEditor()
    editorView = atom.views.getView editor

    if not @editing
      lastSelection = editor.getLastSelection()
      lastSelectionRange = lastSelection.getBufferRange()

      # "superword" is the longest possible text that can be formed from the selected text.
      # For example, if the selected text is "mark-next" in "mark-next-in-any-case", the superword is "mark-next-in-any-case".
      superwordRange = @getSuperwordRangeContainingPosition editor, editor.getCursorBufferPosition()
      superwordText =
        if superwordRange
          editor.getTextInBufferRange superwordRange
        else
          editor.getTextInBufferRange lastSelectionRange

      # If nothing is selected, just select superword and return.
      if lastSelection.isEmpty()
        if superwordRange
          editor.setSelectedBufferRange superwordRange
        return

      # Else, source text is the selected text.
      sourceText = editor.getTextInBufferRange lastSelectionRange

      @editing = true
      @editor = editor
      @checkpoint = editor.createCheckpoint()
      @sourceScroll =
        left: editorView.getScrollLeft()
        top: editorView.getScrollTop()

      # @sourcePosition is at the start of the selection (considers reversed selection).
      @sourcePosition = Point.min(lastSelectionRange.start, lastSelectionRange.end)
      searchStartPosition = lastSelectionRange.end

      # Highlight the source.
      sourceMarker = @highlightRange lastSelectionRange, editor, 'polymorph-source'

      sourceCase = @getCase sourceText, superwordText

      # Monitor source for changes and apply them to the shadows.
      @recentSourceText = editor.getTextInBufferRange sourceMarker.getBufferRange()
      @sourceMarkerOnDidChangeDisposable = editor.onDidChange =>
        sourceText = editor.getTextInBufferRange sourceMarker.getBufferRange()
        textChanged = @recentSourceText isnt sourceText
        @recentSourceText = sourceText
        if textChanged
          editor.transact =>
            for shadowMarker in @getShadowMarkers()
              shadowRange = shadowMarker.getBufferRange()
              shadowText = editor.getTextInBufferRange shadowMarker.getBufferRange()

              # Apply the change in the source to the shadow.
              newShadowText = sourceText

              shadowInverse = @shadows[shadowMarker.id].inverse
              newShadowText = (@[shadowInverse](newShadowText) if shadowInverse isnt 'default') || newShadowText

              shadowCardinality = @shadows[shadowMarker.id].cardinality
              newShadowText = (@[shadowCardinality](newShadowText) if shadowCardinality isnt 'default') || newShadowText

              if shadowCardinality is 'default'
                shadowVerbForm = @shadows[shadowMarker.id].verbForm
                newShadowText = (@[shadowVerbForm](newShadowText) if shadowVerbForm isnt 'default') || newShadowText

                if shadowVerbForm is 'default'
                  shadowAdjectiveForm = @shadows[shadowMarker.id].adjectiveForm
                  newShadowText = (@[shadowAdjectiveForm](newShadowText) if shadowAdjectiveForm isnt 'default') || newShadowText

              shadowColorFormat = @shadows[shadowMarker.id].colorFormat
              newShadowText = (@[shadowColorFormat](newShadowText) if shadowColorFormat isnt 'default') || newShadowText

              if shadowInverse == 'default'
                shadowCase = @shadows[shadowMarker.id].case
                newShadowText = (@[shadowCase](newShadowText) if shadowCase isnt 'default') || newShadowText

              if sourceCase in ['pascalCase', 'camelCase'] && shadowCase in ['pascalCase', 'camelCase']
                charBefore = editor.getTextInBufferRange [@sourcePosition.translate([0, -1]), @sourcePosition]
                # Capitalize shadow text if it's capitalized and source text is at a superword boundary (such as space or paren, or at the beginning of a line).
                if @isCapitalized(shadowText) && @isSuperwordBoundary(charBefore)
                  newShadowText = @capitalize(newShadowText) || newShadowText
                # If source is capitalized...
                else if @isCapitalized(sourceText)
                  # If shadow text is at the beginning of a line or superword boundary, retain its capitalization.
                  charBefore = editor.getTextInBufferRange [shadowRange.start.translate([0, -1]), shadowRange.start]
                  if @isSuperwordBoundary(charBefore)
                    if @isCapitalized(shadowText)
                      newShadowText = @capitalize(newShadowText) || newShadowText
                    else
                      newShadowText = @decapitalize(newShadowText) || newShadowText
                  # Else, capitalize shadow text.
                  else
                    newShadowText = @capitalize(newShadowText) || newShadowText

              else if sourceCase in ['kebabCase', 'snakeCase'] && shadowCase in ['pascalCase', 'camelCase']
                firstChar = if sourceText.length > 0 then sourceText[0] else null
                # Capitalize shadow text if source text begins with a dash (kebab case) or underscore (snake case).
                if (sourceCase is 'kebabCase' && firstChar is '-') || (sourceCase is 'snakeCase' && firstChar is '_')
                  newShadowText = @capitalize(newShadowText) || newShadowText
                # Else, retain capitalization of shadow.
                else
                  if @isCapitalized(shadowText)
                    newShadowText = @capitalize(newShadowText) || newShadowText
                  else
                    newShadowText = @decapitalize(newShadowText) || newShadowText

              # If source case is upcase, shadow text follows the capitalization of source text (upcase, downcase, capitalized).
              else if sourceCase in ['upcase'] && shadowCase in ['pascalCase', 'camelCase']
                if @isUpcase(sourceText)
                  newShadowText = @upcase(newShadowText) || newShadowText
                else if @isDowncase(sourceText)
                  newShadowText = @downcase(newShadowText) || newShadowText
                else if @isCapitalized(sourceText)
                  newShadowText = @capitalize(newShadowText) || newShadowText

              editor.setTextInBufferRange(shadowRange, newShadowText)

    else # if @editing
      searchStartPosition = @lastShadowMatchRange?.end || @sourcePosition

    sourceText = editor.getTextInBufferRange @markers[0].getBufferRange() # @markers[0] is the sourceMarker.

    shadowMatch = @findNextShadow sourceText, @sourcePosition, searchStartPosition, editor, includedForms

    # If a match was found, add it to the set of shadows.
    if shadowMatch
      shadowText = shadowMatch.text
      # Flash and highlight the shadow.
      shadowMarker = @highlightRange shadowMatch.range, editor, 'polymorph-shadow'
      flashMarker = shadowMarker.copy()
      editor.decorateMarker flashMarker, type: 'highlight', class: 'polymorph-shadow-flash'
      setTimeout =>
        flashMarker.destroy()
      , 100

      # Detect the forms of the shadow by comparing with the source.
      shadowInverse = @getShadowInverse shadowText, sourceText
      shadowCardinality = @getShadowCardinality shadowText, sourceText
      shadowVerbForm = @getShadowVerbForm shadowText, sourceText
      shadowAdjectiveForm = @getShadowAdjectiveForm shadowText, sourceText
      shadowColorFormat = @getShadowColorFormat shadowText, sourceText

      # Detect the letter case of the shadow by getting the letter case of its superword.
      shadowSuperwordRange = @getSuperwordRangeContainingPosition editor, shadowMatch.range.start
      shadowCase =
        if shadowSuperwordRange
          shadowSuperwordText = editor.getTextInBufferRange shadowSuperwordRange
          @getCase shadowText, shadowSuperwordText
        else
          'default'

      @shadows[shadowMarker.id] = {case: shadowCase, inverse: shadowInverse, cardinality: shadowCardinality, verbForm: shadowVerbForm, adjectiveForm: shadowAdjectiveForm, colorFormat: shadowColorFormat}
      @lastShadowMatchRange = shadowMatch.range

      # Scroll to the shadow's position.
      editor.scrollToBufferPosition shadowMatch.range.start
    else
      editorView.setScrollLeft @sourceScroll.left
      editorView.setScrollTop @sourceScroll.top
      atom.beep()

  # Result is either null (not found) or {range: range, text: matchText}.
  findNextShadow: (sourceText, sourcePosition, searchStartPosition, editor, includedForms={case: true}) ->
    queryParts = []

    if includedForms.case?
      queryParts = queryParts.concat @constructQueryForEveryCase sourceText, sourcePosition, editor

    if includedForms.inverse?
      inverse = @getInverse(sourceText)
      if sourceText isnt inverse && inverse?
        queryParts = queryParts.concat @constructQueryForEveryCase(inverse, sourcePosition, editor, 'getInverse')

    if includedForms.cardinality?
      singularized = if @isSingular(sourceText) then sourceText else @singularize(sourceText)
      pluralized = if @isPlural(sourceText) then sourceText else @pluralize(sourceText)
      if sourceText is singularized && pluralized?
        queryParts = queryParts.concat @constructQueryForEveryCase(pluralized, sourcePosition, editor, 'singularize')
      else if sourceText is pluralized && singularized?
        queryParts = queryParts.concat @constructQueryForEveryCase(singularized, sourcePosition, editor, 'pluralize')

    if includedForms.verbForm?
      inPast = @toPast sourceText
      inPresent = @toPresent sourceText
      inInfinitive = @toInfinitive sourceText
      inGerund = @toGerund sourceText
      if sourceText is inPast
        for form in [inPresent, inInfinitive, inGerund]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toPast') if form?
      else if sourceText is inPresent
        for form in [inPast, inInfinitive, inGerund]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toPresent') if form?
      else if sourceText is inInfinitive
        for form in [inPast, inPresent, inGerund]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toInfinitive') if form?
      else if sourceText is inGerund
        for form in [inPast, inPresent, inInfinitive]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toGerund') if form?

    if includedForms.adjectiveForm?
      inComparative = @toComparative sourceText
      inSuperlative = @toSuperlative sourceText
      inNoun = @toNoun sourceText
      inAdverb = @toAdverb sourceText
      inAdjective = @toAdjective sourceText
      if sourceText is inComparative
        for form in [inSuperlative, inNoun, inAdverb, inAdjective]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toComparative') if form?
      else if sourceText is inSuperlative
        for form in [inComparative, inNoun, inAdverb, inAdjective]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toSuperlative') if form?
      else if sourceText is inNoun
        for form in [inComparative, inSuperlative, inAdverb, inAdjective]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toNoun') if form?
      else if sourceText is inAdverb
        for form in [inComparative, inSuperlative, inNoun, inAdjective]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toAdverb') if form?
      else if sourceText is inAdjective
        for form in [inComparative, inSuperlative, inNoun, inAdverb]
          queryParts = queryParts.concat @constructQueryForEveryCase(form, sourcePosition, editor, 'toAdjective') if form?

    if includedForms.colorFormat?
      inColorName = @toColorName sourceText
      inColorHex8 = @toColorHex8 sourceText
      inColorHex6 = @toColorHex6 sourceText
      inColorHex3 = @toColorHex3 sourceText
      inColorRgb = @toColorRgb sourceText
      inColorRgba = @toColorRgba sourceText
      inColorPrgb = @toColorPrgb sourceText
      inColorHsl = @toColorHsl sourceText
      inColorHsv = @toColorHsv sourceText
      inColorRgbCompressed = @toColorRgbCompressed sourceText
      inColorRgbaCompressed = @toColorRgbaCompressed sourceText
      inColorPrgbCompressed = @toColorPrgbCompressed sourceText
      inColorHslCompressed = @toColorHslCompressed sourceText
      inColorHsvCompressed = @toColorHsvCompressed sourceText

      if sourceText is inColorName
        for format in [inColorHex8, inColorHex6, inColorHex3, inColorRgb, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorName') if format?
      else if sourceText is inColorHex8
        for format in [inColorName, inColorHex6, inColorHex3, inColorRgb, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHex8') if format?
      else if sourceText is inColorHex6
        for format in [inColorName, inColorHex8, inColorHex3, inColorRgb, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHex6') if format?
      else if sourceText is inColorHex3
        for format in [inColorName, inColorHex6, inColorHex8, inColorRgb, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHex3') if format?
      else if sourceText is inColorRgb
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorRgb') if format?
      else if sourceText is inColorRgba
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgb, inColorPrgb, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorRgb') if format?
      else if sourceText is inColorPrgb
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgb, inColorRgba, inColorHsl, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorPrgb') if format?
      else if sourceText is inColorHsl
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgb, inColorRgba, inColorPrgb, inColorHsv, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHsl') if format?
      else if sourceText is inColorHsv
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgb, inColorRgba, inColorPrgb, inColorHsl, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHsv') if format?
      else if sourceText is inColorRgbCompressed
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorHsl, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorRgbCompressed') if format?
      else if sourceText is inColorRgbaCompressed
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorHsl, inColorRgbCompressed, inColorPrgbCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorRgbaCompressed') if format?
      else if sourceText is inColorPrgbCompressed
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorHsl, inColorRgbCompressed, inColorRgbaCompressed, inColorHslCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorPrgbCompressed') if format?
      else if sourceText is inColorHslCompressed
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorHsl, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHsvCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHslCompressed') if format?
      else if sourceText is inColorHsvCompressed
        for format in [inColorName, inColorHex8, inColorHex6, inColorHex3, inColorRgba, inColorPrgb, inColorHsl, inColorHsv, inColorHsl, inColorRgbCompressed, inColorRgbaCompressed, inColorPrgbCompressed, inColorHslCompressed]
          queryParts = queryParts.concat @constructQueryForEveryCase(format, sourcePosition, editor, 'toColorHsvCompressed') if format?

    # Dedup query parts and sort according to length (prioritize longer matches).
    # If the source is "mark", it will match "marks" (pluralized form), instead of just "mark".
    query = @dedup(queryParts).sort((a, b) -> b.length - a.length).join('|')

    if atom.inDevMode()
      console.log 'sourceText', sourceText, 'query', query

    pattern = new RegExp(query, 'g')

    # Searches for the next match.
    scanRangeEnd = if searchStartPosition.isLessThan(sourcePosition) then sourcePosition else editor.getEofBufferPosition()
    scanRange = [searchStartPosition, scanRangeEnd]
    shadowMatch = null
    editor.scanInBufferRange pattern, scanRange, ({range, matchText, stop}) =>
      shadowMatch = {range: range, text: matchText}
      stop()

    # If no match was found, search from the start of the buffer until before the sourcePosition.
    if not shadowMatch
      wrappedScanRangeStart = if searchStartPosition.isLessThan(sourcePosition) then searchStartPosition else [0, 0]
      wrappedScanRange = [wrappedScanRangeStart, sourcePosition]
      editor.scanInBufferRange pattern, wrappedScanRange, ({range, matchText, stop}) =>
        shadowMatch = {range: range, text: matchText}
        stop()

    shadowMatch

  # Construct list of query parts that includes versions of the sourceText in other letter cases.
  constructQueryForEveryCase: (sourceText, sourcePosition, editor, transformFunction='default') ->
    queryParts = [ escapeRegExp(sourceText) ]

    screamingSnakeCased = @screamingSnakeCase sourceText
    queryParts.push "#{escapeRegExp screamingSnakeCased}"

    snakeCased = @snakeCase sourceText
    queryParts.push "#{escapeRegExp snakeCased}"

    cobolCased = @cobolCase snakeCased
    queryParts.push "#{escapeRegExp cobolCased}"

    kebabCased = @kebabCase snakeCased
    queryParts.push "#{escapeRegExp kebabCased}"

    upcased = @upcase sourceText
    queryParts.push "#{escapeRegExp upcased}"

    downcased = @downcase sourceText
    queryParts.push "#{escapeRegExp downcased}"

    camelCased = @camelCase snakeCased
    queryParts.push "#{escapeRegExp camelCased}"

    {row, column} = sourcePosition
    lineText = editor.lineTextForBufferRow(row)
    transformedSourceText = @[transformFunction](sourceText)
    transformedSnakeCased = @[transformFunction](snakeCased)
    pascalRegex = new RegExp("(^|\\W|_)#{escapeRegExp transformedSnakeCased}$")
    if (snakeCased.length > 0 && snakeCased[0] == '_') || (@snakeCase lineText[0..column+transformedSourceText.length-1]).match pascalRegex
      pascalCased = @pascalCase snakeCased
      queryParts.push "#{escapeRegExp pascalCased}"

    queryParts

  # Deselects the last marked range (shadow).
  skipLastMarked: ->
    shadowMarkers = @getShadowMarkers()
    if shadowMarkers.length > 0
      lastShadowMarker = shadowMarkers[shadowMarkers.length-1]
      # Remove last shadow marker.
      @markers.pop()
      lastShadowMarker.destroy()
      delete @shadows[lastShadowMarker.id]

  # Turns all marked ranges (shadows) into selections.
  selectAllMarked: ->
    ranges = []
    for marker in @markers # Include source marker.
      ranges.push marker.getBufferRange()
    @stopEditing() if @editing
    if ranges.length > 0
      @editor.setSelectedBufferRanges ranges
    else
      atom.beep()

  # Upon pasting, coerce the case of the target range to the original case.
  # Example: If the copied text is "mark-next-in-any" and the target range is "casePreservingPaste", the target range will become "markNextInAny"
  #   because the original case of the target range is camel case.
  casePreservingPaste: ->
    editor = atom.workspace.getActiveTextEditor()
    originalCases = []
    # Get original case of each selection.
    for selection in editor.getSelections()
      selectionRange = selection.getBufferRange()
      selectionText = editor.getTextInBufferRange selectionRange
      superwordRange = @getSuperwordRangeContainingPosition editor, selectionRange.start
      superwordText = editor.getTextInBufferRange superwordRange
      originalCase = @getCase selectionText, superwordText
      originalCases.push originalCase

    editor.transact =>
      editor.pasteText select: true
      # Coerce case of each pasted selection to the original case.
      for [originalCase, pastedSelection] in zip originalCases, editor.getSelections()
        pastedSelectionRange = pastedSelection.getBufferRange()
        pastedSelectionText = editor.getTextInBufferRange pastedSelectionRange
        newSelectionText = @[originalCase](pastedSelectionText) if originalCase isnt 'default'
        pastedSelection.insertText newSelectionText

  highlightRange: (range, editor, klass) ->
    marker = editor.markBufferRange range, invalidate: 'never', persistent: false
    editor.decorateMarker marker, type: 'highlight', class: klass
    @markers.push marker
    marker

  getShadowMarkers: ->
    @markers[1..@markers.length-1] # Do not include source marker.

  getLastShadowMatch: ->
    shadowMarkers = @getShadowMarkers()
    if shadowMarkers.length > 0
      shadowMarker = shadowMarkers[shadowMarkers.length-1]
      @shadows[shadowMarker.id]
    else
      null

  getSuperwordRangeContainingPosition: (editor, position) ->
    rowRange = editor.bufferRangeForBufferRow position.row
    startPosition = rowRange.start
    endPosition = rowRange.end
    editor.backwardsScanInBufferRange /(?![_\-])(\n|^|\W|\s)/, [rowRange.start, position], ({range, stop}) =>
      startPosition = range.start
      # Look for first word position from range.start
      editor.scanInBufferRange /[_\-\w]/, [range.start, rowRange.end], ({range, stop}) =>
        startPosition = range.start
        stop()
      stop()
    editor.scanInBufferRange /(?![_\-])(\n|\W|\s)/, [position, rowRange.end], ({range, stop}) =>
      endPosition = range.start
      stop()
    superwordRange = new Range(startPosition, endPosition)
    if superwordRange.start.isLessThan(superwordRange.end)
      superwordRange
    else
      null

  isSuperwordBoundary: (char) ->
    not char.match /[_\-\w]/

  dedup: (list) ->
    found = new Set()
    uniques = []
    for item in list
      if not found.has(item)
        found.add item
        uniques.push item
    uniques

  getCase: (sourceText, superwordText) ->
    text = if @isInversible(sourceText) then sourceText else superwordText
    textCase = 'default'
    for isCaseFunction in ['isScreamingSnakeCase', 'isSnakeCase', 'isCobolCase', 'isKebabCase', 'isUpcase', 'isDowncase', 'isCamelOrPascalCase']
      if @[isCaseFunction](text)
        textCase = @decapitalize(isCaseFunction[2..-1])
        break
    if textCase is 'camelOrPascalCase'
      textCase =
        if @isPascalCase(text)
          'pascalCase'
        else
          'camelCase'
    textCase

  getShadowInverse: (shadowText, sourceText) ->
    for inverseFunction in ['default', 'getInverse']
      if @snakeCase(shadowText) is @[inverseFunction](@snakeCase(sourceText))
        return inverseFunction
    return 'default'

  getShadowCardinality: (shadowText, sourceText) ->
    for cardinalityFunction in ['default', 'singularize', 'pluralize']
      if @snakeCase(shadowText) is @[cardinalityFunction](@snakeCase(sourceText))
        return cardinalityFunction
    return 'default'

  getShadowVerbForm: (shadowText, sourceText) ->
    for verbFormFunction in ['default', 'toPast', 'toPresent', 'toInfinitive', 'toGerund']
      if @snakeCase(shadowText) is @[verbFormFunction](@snakeCase(sourceText))
        return verbFormFunction
    return 'default'

  getShadowAdjectiveForm: (shadowText, sourceText) ->
    for adjectiveFormFunction in ['default', 'toComparative', 'toSuperlative', 'toNoun', 'toAdverb']
      if @snakeCase(shadowText) is @[adjectiveFormFunction](@snakeCase(sourceText))
        return adjectiveFormFunction
    return 'default'

  getShadowColorFormat: (shadowText, sourceText) ->
    for colorFormatFunction in ['default', 'toColorName',
                                'toColorHex8', 'toColorHex6', 'toColorHex3',
                                'toColorRgb', 'toColorRgba', 'toColorPrgb',
                                'toColorHsl', 'toColorHsv',
                                'toColorRgbCompressed', 'toColorRgbaCompressed', 'toColorPrgbCompressed',
                                'toColorHslCompressed', 'toColorHsvCompressed']
      if @snakeCase(shadowText) is @[colorFormatFunction](@snakeCase(sourceText))
        return colorFormatFunction
    return 'default'

  capitalize: (str) ->
    s = ''
    if str.length > 0
      s += str[0].toUpperCase()
    if str.length > 1
      s += str[1..-1]
    s

  decapitalize: (str) ->
    s = ''
    if str.length > 0
      s += str[0].toLowerCase()
    if str.length > 1
      s += str[1..-1]
    s

  default: (str) ->
    str

  # snake_case
  snakeCase: (str) ->
    trim(str)
    .replace(/(?!^)([A-Z])(?![A-Z_-]|$)/g, '_$1')
    .replace(/[-]+/g, '_')
    .toLowerCase()

  # SCREAMING_SNAKE_CASE
  screamingSnakeCase: (str) ->
    @snakeCase(str)
    .toUpperCase()

  # kebab-case
  kebabCase: (str) ->
    trim(str)
    .replace(/(?!^)([A-Z])/g, '-$1')
    .replace(/[_]+/g, '-')
    .toLowerCase()

  # COBOL-CASE
  cobolCase: (str) ->
    @kebabCase(str)
    .toUpperCase()

  # UPCASE
  upcase: (str) ->
    str.toUpperCase()

  # downcase
  downcase: (str) ->
    str.toLowerCase()

  # camelCase
  camelCase: (str) ->
    @decapitalize trim(str).replace /[_-]+(.)?/g, (match, c) ->
      c?.toUpperCase() || ''

  # PascalCase
  pascalCase: (str) ->
    @capitalize(@camelCase str)

  isDefault: (str) ->
    str

  isUpperCase: (str) ->
    str is str.toUpperCase()

  isLowerCase: (str) ->
    str is str.toLowerCase()

  isCapitalized: (str) ->
    str.length > 0 && @isUpperCase(str[0])

  isSnakeCase: (str) ->
    str.match /_/

  isScreamingSnakeCase: (str) ->
    (str.match /_/) && @isUpperCase(str)

  isKebabCase: (str) ->
    str.match /-/

  isCobolCase: (str) ->
    (str.match /-/) && @isUpperCase(str)

  isCamelCase: (str) ->
    not(str.match /[_-]/) && str.length > 0 && @isLowerCase(str[0])

  isPascalCase: (str) ->
    not(str.match /[_-]/) && @isCapitalized(str)

  isUpcase: (str) ->
    str.length >= 2 && not(str.match /[_-]/) && @isUpperCase(str)

  isDowncase: (str) ->
    str.length >= 2 && not(str.match /[_-]/) && @isLowerCase(str)

  isCamelOrPascalCase: (str) ->
    @isCamelCase(str) || @isPascalCase(str)

  # Applies transformFunction to the last subword, keeping the first subwords as they were.
  # Example: The plural form of "firstChild" will be "firstChildren".
  transformLastSubword: (str, transformFunction) ->
    subwords = str.match subwordRegExp()
    if subwords.length > 1
      [firsts..., last] = subwords
    else
      firsts = []
      last = subwords[0]
    # Prefix can be dashes or underscores.
    matchResult = last.match /([-_]*)(\w+)/
    if matchResult
      [_, prefix, lastSubword] = matchResult
      isCapitalized = @isCapitalized lastSubword
      transformedLast = transformFunction(lastSubword.toLowerCase())
      if transformedLast?
        transformedLast = @capitalize transformedLast if isCapitalized
        return firsts.concat(prefix, [ transformedLast ]).join('')
    return null

  # Applies function only to the last subword.
  applyToLastSubword: (str, func) ->
    subwords = str.match subwordRegExp()
    if subwords.length > 1
      [..., last] = subwords
      matchResult = last.match /([-_]*)(\w+)/
      if matchResult
        [_, _prefix, lastSubword] = matchResult
        return func(lastSubword.toLowerCase())
    return func(str.toLowerCase())

  getInverse: (str) ->
    # Check parens.
    if str.match /^[(){}\[\]]+$/
      str.split('').reverse().map(@getInverseParen).join('')
    # Check XML tags.
    else if str.match /^(<((?![<>])\/{0,1}\w+)>)+$/
      [splits..., _] = str.split('>')
      splits
      .reverse()
      .map((s) ->
        # Match opening tags such as <a>.
        match = s.match /^<((?![\/<>])\w+)$/
        if match
          '</' + match[1] + '>'
        else
          # Match closing tags such as </a>.
          match = s.match /^<\/((?![<>])\w+)$/
          if match
            '<' + match[1] + '>'
          else
            s + '>'
        )
      .join('')
    else
      null

  getInverseParen: (str) ->
    switch str
      when '(' then ')'
      when ')' then '('
      when '{' then '}'
      when '}' then '{'
      when '[' then ']'
      when ']' then '['
      when '<' then '>'
      when '>' then '<'
      else str

  isInversible: (str) ->
    @getInverse(str) != null

  ## Noun forms
  pluralize: (str) ->
    @transformLastSubword str, (last) =>
      # Special cases.
      switch last
        when 'case' then 'cases'
        when 'die' then 'dice' # originally results to "dies"
        else
          if last.match /\W/
            null
          else
            nlp.noun(last).pluralize()

  singularize: (str) ->
    @transformLastSubword str, (last) =>
      # Special cases.
      switch last
        when 'cases' then 'case' # originally results to "cas"
        when 'dice' then 'die' # originally results to "dice"
        else
          if last.match /\W/
            null
          else
            nlp.noun(last).singularize()

  isPlural: (str) ->
    @applyToLastSubword str, (last) =>
      # Special cases.
      switch last
        when 'dice' then true
        else nlp.noun(last).is_plural()

  isSingular: (str) ->
    @applyToLastSubword str, (last) =>
      not @isPlural(last)

  ## Verb forms
  toPast: (str) ->
    @transformLastSubword str, (last) =>
      nlp.verb(last).to_past()

  toPresent: (str) ->
    @transformLastSubword str, (last) =>
      nlp.verb(last).to_present()

  toInfinitive: (str) ->
    @transformLastSubword str, (last) =>
      nlp.verb(last).conjugate().infinitive

  toGerund: (str) ->
    @transformLastSubword str, (last) =>
      nlp.verb(last).conjugate().gerund

  ## Adjective forms
  toComparative: (str) ->
    @transformLastSubword str, (last) =>
      comparative = nlp.adjective(last).to_comparative()
      if comparative.toLowerCase().startsWith('more ')
        null
      else
        comparative

  toSuperlative: (str) ->
    @transformLastSubword str, (last) =>
      superlative = nlp.adjective(last).to_superlative()
      if superlative.toLowerCase().startsWith('most ')
        null
      else
        superlative

  toNoun: (str) ->
    @transformLastSubword str, (last) =>
      nlp.adjective(last).to_noun()

  toAdverb: (str) ->
    @transformLastSubword str, (last) =>
      nlp.adjective(last).to_adverb()

  toAdjective: (str) ->
    @transformLastSubword str, (last) =>
      nlp.adverb(last).to_adjective()

  ## Color formats
  toColorFormat: (str, format) ->
    color = tinycolor(str)
    if color.isValid()
      color.toString(format)
    else
      null

  toColorName: (str) ->
    @toColorFormat str, 'name'

  toColorHex8: (str) ->
    @toColorFormat str, 'hex8'

  toColorHex6: (str) ->
    @toColorFormat str, 'hex6'

  toColorHex3: (str) ->
    @toColorFormat str, 'hex3'

  toColorRgb: (str) ->
    @toColorFormat str, 'rgb'

  # Converts "rgb(255, 0, 0)" to "rgba(255, 0, 0, 1)".
  toColorRgba: (str) ->
    rgb = @toColorFormat(str, 'rgb')
    if rgb
      rgb[0..2] + 'a' + rgb[3..-2] + ', 1)'
    else
      null

  toColorPrgb: (str) ->
    @toColorFormat str, 'prgb'

  toColorHsl: (str) ->
    @toColorFormat str, 'hsl'

  toColorHsv: (str) ->
    @toColorFormat str, 'hsv'

  toColorRgbCompressed: (str) ->
    @toColorRgb(str)?.replace(/\s/g, '')

  toColorRgbaCompressed: (str) ->
    @toColorRgba(str)?.replace(/\s/g, '')

  toColorPrgbCompressed: (str) ->
    @toColorPrgb(str)?.replace(/\s/g, '')

  toColorHslCompressed: (str) ->
    @toColorHsl(str)?.replace(/\s/g, '')

  toColorHsvCompressed: (str) ->
    @toColorHsv(str)?.replace(/\s/g, '')

#------------------------------------------------------------------------------
# From underscore-plus:
escapeRegExp = (str) ->
  str?.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&') || ''

# From cursor.coffee:
subwordRegExp = (options={}) ->
  # nonWordCharacters = @config.get('editor.nonWordCharacters', scope: @getScopeDescriptor())
  nonWordCharacters = atom.config.get('editor.nonWordCharacters')
  lowercaseLetters = 'a-z\\u00DF-\\u00F6\\u00F8-\\u00FF'
  uppercaseLetters = 'A-Z\\u00C0-\\u00D6\\u00D8-\\u00DE'
  snakeCamelSegment = "[#{uppercaseLetters}]?[#{lowercaseLetters}]+"
  segments = [
    "^[\t ]+",
    "[\t ]+$",
    "[#{uppercaseLetters}]+(?![#{lowercaseLetters}])",
    "\\d+"
  ]
  if options.backwards
    segments.push("#{snakeCamelSegment}_*")
    segments.push("[#{escapeRegExp(nonWordCharacters)}]+\\s*")
  else
    segments.push("_*#{snakeCamelSegment}")
    segments.push("\\s*[#{escapeRegExp(nonWordCharacters)}]+")
  segments.push("_+")
  new RegExp(segments.join("|"), "g")

trim = (str) ->
  if String::trim? then str.trim() else str.replace /^\s+|\s+$/g, ''

# https://coffeescript-cookbook.github.io/chapters/arrays/zip-function
zip = () ->
  lengthArray = (arr.length for arr in arguments)
  length = Math.min(lengthArray...)
  for i in [0...length]
    arr[i] for arr in arguments

#------------------------------------------------------------------------------
# # # TODO: Configurable special cases.
# # # TODO: Fix undo behavior when @editing is true (group change in source with changes in shadows).
# # # TODO: isPast, isPresent, isInfinitive, isGerund (compare with infinitive)
# # # TODO: Adjective base form (e.g. if the source is "quicker", should match "quick").
# # # TODO: Match "runner" when source is "run" or "running".
# # # TODO: "one" should match "1", "one hundred" should match "100"?
# # # TODO: Display number of shadows in bottom panel?
