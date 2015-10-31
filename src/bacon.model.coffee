id = (x) -> x

nonEmpty = (x) -> x.length > 0

isModel = (obj) -> obj instanceof Bacon.Property
isArray = (obj) -> obj instanceof Array
isObject = (obj) -> typeof obj == "object"
isEqual = (a, b) -> a == b

fold = (xs, seed, f) ->
  for x in xs
    seed = f(seed, x)
  seed

shallowCopy = (x, key, value) ->
  copy = if isArray(x)
    []
  else
    {}

  copy[k] = v for k, v of x

  if key?
    copy[key] = value

  copy

factory = (Bacon) ->
  _ = Bacon._
  idCounter = 1

  Model = Bacon.Model = (initValue) ->
    myId = idCounter++
    currentValue = undefined

    modificationBus = new Bacon.Bus()
    syncBus         = new Bacon.Bus()

    valueWithSource = Bacon.update(
      { initial: true },

      [modificationBus], (({value}, {source, f}) ->
        newValue = f(value)
        modStack = [myId]
        changed = newValue != value
        {source, value: newValue, modStack, changed}),

      [syncBus], ((__, syncEvent) -> syncEvent)
    )
      .filter("!.initial")
      .skipDuplicates(isEqual)
      .changes()
      .toProperty()

    model = valueWithSource
      .map((x) -> x.value)
      .skipDuplicates(isEqual)

    model.dispatcher.subscribe (event) ->
      if event.hasValue()
        currentValue = event.value()

    model.id ||= myId

    model.addSyncSource = (syncEvents) ->
      source = syncEvents
        .filter((e) -> e.changed && !_.contains(e.modStack, myId))
        .map((e) -> shallowCopy(e, "modStack", e.modStack.concat([myId])))
        .map((e) -> valueLens.set(e, model.syncConverter(valueLens.get(e))))

      syncBus.plug(source)

    model.apply = (source) ->
      modificationBus.plug(source.toEventStream().map((f) -> {source, f}))
      valueWithSource.changes()
        .filter((change) -> change.source != source)
        .map((change) -> change.value)

    model.addSource = (source) -> model.apply(source.map((v) -> (->v)))

    model.modify = (f) -> model.apply(Bacon.once(f))

    model.set = (value) -> model.modify(-> value)

    model.get = -> currentValue

    model.syncEvents = -> valueWithSource.toEventStream()

    model.bind = (other) ->
      @addSyncSource(other.syncEvents())
      other.addSyncSource(@syncEvents())

    model.lens = (lens) ->
      lens = Lens(lens)
      lensed = Model()

      @addSyncSource(model.sampledBy(lensed.syncEvents(), (full, lensedSync) ->
        valueLens.set(lensedSync, lens.set(full, lensedSync.value))
      ))

      lensed.addSyncSource(@syncEvents().map((e) ->
        valueLens.set(e, lens.get(e.value))))
      lensed

    model.syncConverter = id

    if (arguments.length >= 1)
      model.set(initValue)

    model

  Model.combine = (template) ->
    if !isObject(template)
      Model(template)
    else if isModel(template)
      template
    else
      initValue = if template instanceof Array then [] else {}
      model = Model(initValue)
      for key, value of template
        lens = Lens.objectLens(key)
        lensedModel = model.lens(lens)
        lensedModel.bind(Model.combine(value))
      model

  Bacon.Binding = ({ initValue, get, events, set }) ->
    inputs = events.map(get)

    if initValue?
      set(initValue)
    else
      initValue = get()

    model = Model(initValue)

    model
      .addSource(inputs)
      .assign(set)

    model

  Lens = Bacon.Lens = (lens) ->
    if isObject(lens)
      lens
    else
      Lens.objectLens(lens)

  Lens.id = Lens({
    get: (x) -> x
    set: (__, value) -> value
  })

  Lens.objectLens = (path) ->
    objectKeyLens = (key) ->
      Lens({
        get: (x) -> x?[key]
        set: (context, value) -> shallowCopy(context, key, value)
      })

    keys = _.filter(nonEmpty, path.split("."))
    Lens.compose(_.map(objectKeyLens, keys)...)

  Lens.compose = (args...) ->
    compose2 = (outer, inner) ->
      Lens({
        get: (x) -> inner.get(outer.get(x))
        set: (context, value) ->
          innerContext = outer.get(context)
          newInnerContext = inner.set(innerContext, value)
          outer.set(context, newInnerContext)
      })

    fold(args, Lens.id, compose2)

  valueLens = Lens.objectLens("value")

  Model

if module? && module.exports?
  Bacon = require("baconjs")
  module.exports = factory(Bacon)
else
  if typeof define == "function" and define.amd
    define ["bacon"], factory
  else
    factory(this.Bacon)
