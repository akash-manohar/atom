path = require 'path'
temp = require 'temp'
PaneContainerView = require '../src/pane-container-view'
PaneView = require '../src/pane-view'
{_, $, View, $$} = require 'atom'

describe "PaneContainerView", ->
  [TestView, container, pane1, pane2, pane3] = []

  beforeEach ->
    class TestView extends View
      atom.deserializers.add(this)
      @deserialize: ({name}) -> new TestView(name)
      @content: -> @div tabindex: -1
      initialize: (@name) -> @text(@name)
      serialize: -> { deserializer: 'TestView', @name }
      getUri: -> path.join(temp.dir, @name)
      save: -> @saved = true
      isEqual: (other) -> @name is other?.name

    container = new PaneContainerView
    pane1 = new PaneView(new TestView('1'))
    container.setRoot(pane1)
    pane2 = pane1.splitRight(new TestView('2'))
    pane3 = pane2.splitDown(new TestView('3'))

  afterEach ->
    atom.deserializers.remove(TestView)

  describe ".focusNextPane()", ->
    it "focuses the pane following the focused pane or the first pane if no pane has focus", ->
      container.attachToDom()
      container.focusNextPane()
      expect(pane1.activeItem).toMatchSelector ':focus'
      container.focusNextPane()
      expect(pane2.activeItem).toMatchSelector ':focus'
      container.focusNextPane()
      expect(pane3.activeItem).toMatchSelector ':focus'
      container.focusNextPane()
      expect(pane1.activeItem).toMatchSelector ':focus'

  describe ".focusPreviousPane()", ->
    it "focuses the pane preceding the focused pane or the last pane if no pane has focus", ->
      container.attachToDom()
      $(document.body).focus() # clear focus

      container.focusPreviousPane()
      expect(pane3.activeItem).toMatchSelector ':focus'
      container.focusPreviousPane()
      expect(pane2.activeItem).toMatchSelector ':focus'
      container.focusPreviousPane()
      expect(pane1.activeItem).toMatchSelector ':focus'
      container.focusPreviousPane()
      expect(pane3.activeItem).toMatchSelector ':focus'

  describe ".getActivePane()", ->
    it "returns the most-recently focused pane", ->
      focusStealer = $$ -> @div tabindex: -1, "focus stealer"
      focusStealer.attachToDom()
      container.attachToDom()

      pane2.focus()
      expect(container.getFocusedPane()).toBe pane2
      expect(container.getActivePane()).toBe pane2

      focusStealer.focus()
      expect(container.getFocusedPane()).toBeUndefined()
      expect(container.getActivePane()).toBe pane2

      pane3.focus()
      expect(container.getFocusedPane()).toBe pane3
      expect(container.getActivePane()).toBe pane3

  describe ".eachPane(callback)", ->
    it "runs the callback with all current and future panes until the subscription is cancelled", ->
      panes = []
      subscription = container.eachPane (pane) -> panes.push(pane)
      expect(panes).toEqual [pane1, pane2, pane3]

      panes = []
      pane4 = pane3.splitRight(pane3.copyActiveItem())
      expect(panes).toEqual [pane4]

      panes = []
      subscription.off()
      pane4.splitDown()
      expect(panes).toEqual []

  describe ".saveAll()", ->
    it "saves all open pane items", ->
      pane1.activateItem(new TestView('4'))

      container.saveAll()

      for pane in container.getPanes()
        for item in pane.getItems()
          expect(item.saved).toBeTruthy()

  describe ".confirmClose()", ->
    it "returns true after modified files are saved", ->
      pane1.itemAtIndex(0).shouldPromptToSave = -> true
      pane2.itemAtIndex(0).shouldPromptToSave = -> true
      spyOn(atom, "confirm").andReturn(0)

      saved = container.confirmClose()

      runs ->
        expect(saved).toBeTruthy()
        expect(atom.confirm).toHaveBeenCalled()

    it "returns false if the user cancels saving", ->
      pane1.itemAtIndex(0).shouldPromptToSave = -> true
      pane2.itemAtIndex(0).shouldPromptToSave = -> true
      spyOn(atom, "confirm").andReturn(1)

      saved = container.confirmClose()

      runs ->
        expect(saved).toBeFalsy()
        expect(atom.confirm).toHaveBeenCalled()

  describe "serialization", ->
    it "can be serialized and deserialized, and correctly adjusts dimensions of deserialized panes after attach", ->
      newContainer = atom.deserializers.deserialize(container.serialize())
      expect(newContainer.find('.pane-row > :contains(1)')).toExist()
      expect(newContainer.find('.pane-row > .pane-column > :contains(2)')).toExist()
      expect(newContainer.find('.pane-row > .pane-column > :contains(3)')).toExist()

      newContainer.height(200).width(300).attachToDom()
      expect(newContainer.find('.pane-row > :contains(1)').width()).toBe 150
      expect(newContainer.find('.pane-row > .pane-column > :contains(2)').height()).toBe 100

    it "removes empty panes on deserialization", ->
      # only deserialize pane 1's view successfully
      TestView.deserialize = ({name}) -> new TestView(name) if name is '1'
      newContainer = atom.deserializers.deserialize(container.serialize())
      expect(newContainer.find('.pane-row, .pane-column')).not.toExist()
      expect(newContainer.find('> :contains(1)')).toExist()

  describe "pane-container:active-pane-item-changed", ->
    [pane1, item1a, item1b, item2a, item2b, item3a, container, activeItemChangedHandler] = []
    beforeEach ->
      item1a = new TestView('1a')
      item1b = new TestView('1b')
      item2a = new TestView('2a')
      item2b = new TestView('2b')
      item3a = new TestView('3a')

      container = new PaneContainerView
      container.attachToDom()
      pane1 = new PaneView(item1a)
      container.setRoot(pane1)

      activeItemChangedHandler = jasmine.createSpy("activeItemChangedHandler")
      container.on 'pane-container:active-pane-item-changed', activeItemChangedHandler

    describe "when there are no panes", ->
      it "is triggered when a new pane containing a pane item is added", ->
        container.setRoot()
        expect(container.getPanes().length).toBe 0
        activeItemChangedHandler.reset()

        pane = new PaneView(item1a)
        container.setRoot(pane)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item1a

    describe "when there is one pane", ->
      it "is triggered when a new pane item is added", ->
        pane1.activateItem(item1b)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item1b

      it "is not triggered when the active pane item is shown again", ->
        pane1.activateItem(item1a)
        expect(activeItemChangedHandler).not.toHaveBeenCalled()

      it "is triggered when switching to an existing pane item", ->
        pane1.activateItem(item1b)
        activeItemChangedHandler.reset()

        pane1.activateItem(item1a)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item1a

      it "is triggered when the active pane item is destroyed", ->
        pane1.activateItem(item1b)
        activeItemChangedHandler.reset()

        pane1.destroyItem(item1b)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item1a

      it "is not triggered when an inactive pane item is destroyed", ->
        pane1.activateItem(item1b)
        activeItemChangedHandler.reset()

        pane1.destroyItem(item1a)
        expect(activeItemChangedHandler).not.toHaveBeenCalled()

      it "is triggered when all pane items are destroyed", ->
        pane1.destroyItem(item1a)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toBe undefined

      it "is triggered when the pane is destroyed", ->
        pane1.remove()
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toBe undefined

    describe "when there are two panes", ->
      [pane2] = []

      beforeEach ->
        pane2 = pane1.splitLeft(item2a)
        activeItemChangedHandler.reset()

      it "is triggered when a new pane item is added to the active pane", ->
        pane2.activateItem(item2b)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item2b

      it "is not triggered when a new pane item is added to an inactive pane", ->
        pane1.activateItem(item1b)
        expect(activeItemChangedHandler).not.toHaveBeenCalled()

      it "is triggered when the active pane's active item is destroyed", ->
        pane2.activateItem(item2b)
        activeItemChangedHandler.reset()

        pane2.destroyItem(item2b)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item2a

      it "is not triggered when an inactive pane's active item is destroyed", ->
        pane1.activateItem(item1b)
        activeItemChangedHandler.reset()

        pane1.destroyItem(item1b)
        expect(activeItemChangedHandler).not.toHaveBeenCalled()

      it "is triggered when the active pane is destroyed", ->
        pane2.remove()
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item1a

      it "is not triggered when an inactive pane is destroyed", ->
        pane1.remove()
        expect(activeItemChangedHandler).not.toHaveBeenCalled()

      it "is triggered when the active pane is changed", ->
        pane1.activate()
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item1a

    describe "when there are multiple panes", ->
      beforeEach ->
        pane2 = pane1.splitRight(item2a)
        activeItemChangedHandler.reset()

      it "is triggered when a new pane is added", ->
        pane2.splitDown(item3a)
        expect(activeItemChangedHandler.callCount).toBe 1
        expect(activeItemChangedHandler.argsForCall[0][1]).toEqual item3a

      it "is not triggered when an inactive pane is destroyed", ->
        pane3 = pane2.splitDown(item3a)
        activeItemChangedHandler.reset()

        pane1.remove()
        pane2.remove()
        expect(activeItemChangedHandler).not.toHaveBeenCalled()