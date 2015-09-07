(function() {
  var Bacon, fold, id, init, isArray, isEqual, isModel, isObject, nonEmpty, shallowCopy,
    slice = [].slice;

  id = function(x) {
    return x;
  };

  nonEmpty = function(x) {
    return x.length > 0;
  };

  isModel = function(obj) {
    return obj instanceof Bacon.Property;
  };

  isArray = function(obj) {
    return obj instanceof Array;
  };

  isObject = function(obj) {
    return typeof obj === "object";
  };

  isEqual = function(a, b) {
    return a === b;
  };

  fold = function(xs, seed, f) {
    var i, len, x;
    for (i = 0, len = xs.length; i < len; i++) {
      x = xs[i];
      seed = f(seed, x);
    }
    return seed;
  };

  shallowCopy = function(x, key, value) {
    var copy, k, v;
    copy = isArray(x) ? [] : {};
    for (k in x) {
      v = x[k];
      copy[k] = v;
    }
    if (key != null) {
      copy[key] = value;
    }
    return copy;
  };

  init = function(Bacon) {
    var Lens, Model, _, idCounter, valueLens;
    _ = Bacon._;
    idCounter = 1;
    Model = Bacon.Model = function(initValue) {
      var currentValue, model, modificationBus, myId, syncBus, valueWithSource;
      myId = idCounter++;
      currentValue = void 0;
      modificationBus = new Bacon.Bus();
      syncBus = new Bacon.Bus();
      valueWithSource = Bacon.update({
        initial: true
      }, [modificationBus], (function(arg, arg1) {
        var changed, f, modStack, newValue, source, value;
        value = arg.value;
        source = arg1.source, f = arg1.f;
        newValue = f(value);
        modStack = [myId];
        changed = newValue !== value;
        return {
          source: source,
          value: newValue,
          modStack: modStack,
          changed: changed
        };
      }), [syncBus], (function(__, syncEvent) {
        return syncEvent;
      })).filter("!.initial").skipDuplicates(isEqual).changes().toProperty();
      model = valueWithSource.map(".value").skipDuplicates(isEqual);
      model.dispatcher.subscribe(function(event) {
        if (event.hasValue()) {
          return currentValue = event.value();
        }
      });
      model.id || (model.id = myId);
      model.addSyncSource = function(syncEvents) {
        var source;
        source = syncEvents.filter(function(e) {
          return e.changed && !_.contains(e.modStack, myId);
        }).map(function(e) {
          return shallowCopy(e, "modStack", e.modStack.concat([myId]));
        }).map(function(e) {
          return valueLens.set(e, model.syncConverter(valueLens.get(e)));
        });
        return syncBus.plug(source);
      };
      model.apply = function(source) {
        modificationBus.plug(source.toEventStream().map(function(f) {
          return {
            source: source,
            f: f
          };
        }));
        return valueWithSource.changes().filter(function(change) {
          return change.source !== source;
        }).map(function(change) {
          return change.value;
        });
      };
      model.addSource = function(source) {
        return model.apply(source.map(function(v) {
          return function() {
            return v;
          };
        }));
      };
      model.modify = function(f) {
        return model.apply(Bacon.once(f));
      };
      model.set = function(value) {
        return model.modify(function() {
          return value;
        });
      };
      model.get = function() {
        return currentValue;
      };
      model.syncEvents = function() {
        return valueWithSource.toEventStream();
      };
      model.bind = function(other) {
        this.addSyncSource(other.syncEvents());
        return other.addSyncSource(this.syncEvents());
      };
      model.lens = function(lens) {
        var lensed;
        lens = Lens(lens);
        lensed = Model();
        this.addSyncSource(model.sampledBy(lensed.syncEvents(), function(full, lensedSync) {
          return valueLens.set(lensedSync, lens.set(full, lensedSync.value));
        }));
        lensed.addSyncSource(this.syncEvents().map(function(e) {
          return valueLens.set(e, lens.get(e.value));
        }));
        return lensed;
      };
      model.syncConverter = id;
      if (arguments.length >= 1) {
        model.set(initValue);
      }
      return model;
    };
    Model.combine = function(template) {
      var initValue, key, lens, lensedModel, model, value;
      if (!isObject(template)) {
        return Model(template);
      } else if (isModel(template)) {
        return template;
      } else {
        initValue = template instanceof Array ? [] : {};
        model = Model(initValue);
        for (key in template) {
          value = template[key];
          lens = Lens.objectLens(key);
          lensedModel = model.lens(lens);
          lensedModel.bind(Model.combine(value));
        }
        return model;
      }
    };
    Bacon.Binding = function(arg) {
      var events, get, initValue, inputs, model, set;
      initValue = arg.initValue, get = arg.get, events = arg.events, set = arg.set;
      inputs = events.map(get);
      if (initValue != null) {
        set(initValue);
      } else {
        initValue = get();
      }
      model = Model(initValue);
      model.addSource(inputs).assign(set);
      return model;
    };
    Bacon.localStorageProperty = function(key) {
      var get;
      get = function() {
        return localStorage.getItem(key);
      };
      return Bacon.Binding({
        initValue: get(),
        get: get,
        events: Bacon.never(),
        set: function(value) {
          return localStorage.setItem(key, value);
        }
      });
    };
    Lens = Bacon.Lens = function(lens) {
      if (isObject(lens)) {
        return lens;
      } else {
        return Lens.objectLens(lens);
      }
    };
    Lens.id = Lens({
      get: function(x) {
        return x;
      },
      set: function(__, value) {
        return value;
      }
    });
    Lens.objectLens = function(path) {
      var keys, objectKeyLens;
      objectKeyLens = function(key) {
        return Lens({
          get: function(x) {
            return x != null ? x[key] : void 0;
          },
          set: function(context, value) {
            return shallowCopy(context, key, value);
          }
        });
      };
      keys = _.filter(nonEmpty, path.split("."));
      return Lens.compose.apply(Lens, _.map(objectKeyLens, keys));
    };
    Lens.compose = function() {
      var args, compose2;
      args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
      compose2 = function(outer, inner) {
        return Lens({
          get: function(x) {
            return inner.get(outer.get(x));
          },
          set: function(context, value) {
            var innerContext, newInnerContext;
            innerContext = outer.get(context);
            newInnerContext = inner.set(innerContext, value);
            return outer.set(context, newInnerContext);
          }
        });
      };
      return fold(args, Lens.id, compose2);
    };
    valueLens = Lens.objectLens("value");
    return Bacon;
  };

  if ((typeof module !== "undefined" && module !== null) && (module.exports != null)) {
    Bacon = require("baconjs");
    module.exports = init(Bacon);
  } else {
    if (typeof define === "function" && define.amd) {
      define(["bacon"], init);
    } else {
      init(this.Bacon);
    }
  }

}).call(this);
