///| Yoga Layout Engine Type Definitions

///| MoonBit bindings for Yoga (Flexbox layout engine)

///|
/// Align values control how children are aligned along the cross axis
pub(all) enum Align {
  Auto
  FlexStart
  Center
  FlexEnd
  Stretch
  Baseline
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq, Show)

///|
/// Box sizing mode
pub(all) enum BoxSizing {
  BorderBox
  ContentBox
} derive(Eq, Show)

///|
/// Dimension type
pub(all) enum Dimension {
  Width
  Height
} derive(Eq, Show)

///|
/// Text direction
pub(all) enum Direction {
  Inherit
  LTR // Left to Right
  RTL // Right to Left
} derive(Eq, Show)

///|
/// Display type
pub(all) enum Display {
  Flex
  None
  Contents
} derive(Eq, Show)

///|
/// Edge for margin/padding/border
pub(all) enum Edge {
  Left
  Top
  Right
  Bottom
  Start
  End
  Horizontal
  Vertical
  All
} derive(Eq, Show)

///|
/// Flex direction
pub(all) enum FlexDirection {
  Column
  ColumnReverse
  Row
  RowReverse
} derive(Eq, Show)

///|
/// Gutter type
pub(all) enum Gutter {
  Column
  Row
  All
} derive(Eq, Show)

///|
/// Justify content values
pub(all) enum Justify {
  FlexStart
  Center
  FlexEnd
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq, Show)

///|
/// Wrap mode
pub(all) enum Wrap {
  NoWrap
  Wrap
  WrapReverse
} derive(Eq, Show)

///|
/// Position type
pub(all) enum PositionType {
  Static
  Relative
  Absolute
} derive(Eq, Show)

///|
/// Overflow handling
pub(all) enum Overflow {
  Visible
  Hidden
  Scroll
} derive(Eq, Show)

///|
/// Unit type for values
pub(all) enum YogaUnit {
  Undefined
  Point
  Percent
  Auto
} derive(Eq, Show)

///|
/// Measure mode for custom measurements
pub(all) enum MeasureMode {
  Undefined
  Exactly
  AtMost
} derive(Eq, Show)

///|
/// Log level for debugging
pub(all) enum LogLevel {
  Error
  Warn
  Info
  Debug
  Verbose
  Fatal
} derive(Eq, Show)

///|
/// Value type that can be a number, percentage, or auto
pub(all) struct Value {
  value : Float
  unit : YogaUnit
} derive(Eq, Show)

///|
/// Create value constructors
pub fn Value::point(value : Float) -> Value {
  { value, unit: YogaUnit::Point }
}

///|
pub fn Value::percent(value : Float) -> Value {
  { value, unit: YogaUnit::Percent }
}

///|
pub fn Value::auto() -> Value {
  { value: 0.0, unit: YogaUnit::Auto }
}

///|
pub fn Value::undefined() -> Value {
  { value: 0.0, unit: YogaUnit::Undefined }
}
