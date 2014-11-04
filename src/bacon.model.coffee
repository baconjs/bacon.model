init = (Bacon) ->
  id = (x) -> x
  nonEmpty = (x) -> x.length > 0
  fold = (xs, seed, f) ->
    for x in xs
      seed = f(seed, x)
    seed
  isModel = (obj) -> obj instanceof Bacon.Property

  globalModCount = 0
  idCounter = 1

  defaultEquals = (a, b) -> a == b
  sameValue = (eq) -> (a, b) -> !a.initial && eq(a.value, b.value)
  
  Model = Bacon.Model = (initValue) ->
    myId = idCounter++
    eq = defaultEquals
    myModCount = 0
    modificationBus = new Bacon.Bus()
    syncBus = new Bacon.Bus()
    currentValue = undefined
    valueWithSource = Bacon.update(
      { initial: true },
      [modificationBus], (({value}, {source, f}) -> 
        newValue = f(value)
        modStack = [myId]
        changed = newValue != value
        {source, value: newValue, modStack, changed}),
      [syncBus], ((_, syncEvent) -> syncEvent)
    ).skipDuplicates(sameValue(eq)).changes().toProperty()
    model = valueWithSource.map(".value").skipDuplicates(eq)
    model.dispatcher.subscribe (event) ->
      if event.hasValue()
        currentValue = event.value()
    model.id = myId if not model.id # Patch for Bacon.js < 0.7
    model.addSyncSource = (syncEvents) ->
      syncBus.plug(syncEvents
        .filter((e) -> 
          e.changed && !Bacon._.contains(e.modStack, myId)
        )
        .doAction(-> Bacon.Model.syncCount++)
        .map((e) -> shallowCopy e, "modStack", e.modStack.concat([myId]))
        .map((e) -> valueLens.set(e, model.syncConverter(valueLens.get(e))))
      )
    model.apply = (source) -> 
      modificationBus.plug(source.toEventStream().map((f) -> {source, f}))
      valueWithSource.changes()
        .filter((change) -> change.source != source)
        .map((change) -> change.value)
    model.addSource = (source) -> model.apply(source.map((v) -> (->v)))
    model.modify = (f) -> 
      model.apply(Bacon.once(f))
    model.set = (value) -> model.modify(-> value)
    model.get = -> currentValue
    model.syncEvents = -> valueWithSource.toEventStream()
    model.bind = (other) ->
      this.addSyncSource(other.syncEvents())
      other.addSyncSource(this.syncEvents())
    model.lens = (lens) ->
      lens = Lens(lens)
      lensed = Model()
      this.addSyncSource(model.sampledBy(lensed.syncEvents(), (full, lensedSync) ->
        valueLens.set(lensedSync, lens.set(full, lensedSync.value))
      ))
      lensed.addSyncSource(this.syncEvents().map((e) -> 
        valueLens.set(e, lens.get(e.value))))
      lensed
    model.syncConverter = id
    if (arguments.length >= 1)
      model.set initValue
    model

  Bacon.Model.syncCount = 0

  Model.combine = (template) ->
    if typeof template != "object"
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

  Bacon.Binding = ({ initValue, get, events, set}) ->
    inputs = events.map(get)
    if initValue?
      set(initValue)
    else
      initValue = get()
    model = Bacon.Model(initValue)
    externalChanges = model.addSource(inputs)
    externalChanges.assign(set)
    model

  Lens = Bacon.Lens = (lens) ->
    if typeof lens == "object"
      lens
    else
      Lens.objectLens(lens)

  Lens.id = Lens {
    get: (x) -> x
    set: (context, value) -> value
  }

  Lens.objectLens = (path) ->
    objectKeyLens = (key) -> 
      Lens {
        get: (x) -> x?[key]
        set: (context, value) -> shallowCopy context, key, value
      }
    keys = Bacon._.filter(nonEmpty, path.split("."))
    Lens.compose(Bacon._.map(objectKeyLens, keys)...)

  Lens.compose = (args...) -> 
    compose2 = (outer, inner) -> Lens {
      get: (x) -> inner.get(outer.get(x)),
      set: (context, value) ->
        innerContext = outer.get(context)
        newInnerContext = inner.set(innerContext, value)
        outer.set(context, newInnerContext)
    }
    fold(args, Lens.id, compose2)
  
  valueLens = Lens.objectLens("value")

  shallowCopy = (x, key, value) ->
    copy = if x instanceof Array
      []
    else
      {}
    for k, v of x
      copy[k] = v
    if key?
      copy[key] = value
    copy

  Bacon

if module?
  Bacon = require("baconjs")
  module.exports = init(Bacon)
else
  if typeof define == "function" and define.amd
    define ["bacon"], init
  else
    init(this.Bacon)
