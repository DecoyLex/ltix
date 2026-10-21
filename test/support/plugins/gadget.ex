defmodule TestPlugins.Gadget do
  @moduledoc false
  # A third-party provider whose extending modules each declare a property,
  # without a `resolve/1` of its own.
  use Ltix.Provider, hook: [Ltix.Property]
end

defmodule TestPlugins.GadgetColor do
  @moduledoc false
  use TestPlugins.Gadget,
    property: "color",
    name: :color
end

defmodule TestPlugins.OtherGadgetColor do
  @moduledoc false
  # Declares the property `TestPlugins.GadgetColor` declares.
  use TestPlugins.Gadget,
    property: "color",
    name: :other_color
end
