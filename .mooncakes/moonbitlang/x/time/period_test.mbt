// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
test "of" {
  @debug.debug_inspect(
    @time.Period::of(years=1000, months=24, days=365),
    content="P1000Y24M365D",
  )
}

///|
test "from_string" {
  @debug.debug_inspect(@time.Period::from_string("P10Y2M3D"), content="P10Y2M3D")
  @debug.debug_inspect(@time.Period::from_string("P-10Y-2M-3D"), content="P-10Y-2M-3D")
  @debug.debug_inspect(@time.Period::from_string("P2M3D10Y"), content="P2M3D")
  assert_true((try? @time.Period::from_string("10Y")) is Err(_))
  assert_true((try? @time.Period::from_string("10Y0M")) is Err(_))
  assert_true((try? @time.Period::from_string("P10YT3H")) is Err(_))
  assert_true((try? @time.Period::from_string("P2.5Y")) is Err(_))
}

///|
test "getters" {
  let p = @time.Period::of(years=1, months=2, days=3)
  @debug.debug_inspect(p.years(), content="1")
  @debug.debug_inspect(p.months(), content="2")
  @debug.debug_inspect(p.days(), content="3")
  @debug.debug_inspect(p.to_total_months(), content="14")
}

///|
test "is_zero" {
  @debug.debug_inspect(@time.Period::zero().is_zero(), content="true")
  @debug.debug_inspect(@time.Period::of().is_zero(), content="true")
  @debug.debug_inspect(@time.Period::of(years=1).is_zero(), content="false")
  @debug.debug_inspect(@time.Period::of(months=1).is_zero(), content="false")
  @debug.debug_inspect(@time.Period::of(days=1).is_zero(), content="false")
}

///|
test "is_neg" {
  @debug.debug_inspect(@time.Period::of().is_neg(), content="false")
  @debug.debug_inspect(@time.Period::of(years=1, months=1).is_neg(), content="false")
  @debug.debug_inspect(@time.Period::of(years=-1, months=1).is_neg(), content="true")
}

///|
test "add_years" {
  let p = @time.Period::of(years=10)
  @debug.debug_inspect(p.add_years(0), content="P10Y")
  @debug.debug_inspect(p.add_years(1), content="P11Y")
  @debug.debug_inspect(p.add_years(-1), content="P9Y")
}

///|
test "add_months" {
  let p = @time.Period::of(months=10)
  @debug.debug_inspect(p.add_months(0), content="P10M")
  @debug.debug_inspect(p.add_months(1), content="P11M")
  @debug.debug_inspect(p.add_months(-1), content="P9M")
}

///|
test "add_weeks" {
  let p = @time.Period::of(days=10)
  @debug.debug_inspect(p.add_weeks(0), content="P10D")
  @debug.debug_inspect(p.add_weeks(1), content="P17D")
  @debug.debug_inspect(p.add_weeks(-1), content="P3D")
}

///|
test "add_days" {
  let p = @time.Period::of(days=10)
  @debug.debug_inspect(p.add_days(0), content="P10D")
  @debug.debug_inspect(p.add_days(1), content="P11D")
  @debug.debug_inspect(p.add_days(-1), content="P9D")
}

///|
test "with_years" {
  @debug.debug_inspect(@time.Period::of(years=1).with_years(1), content="P1Y")
  @debug.debug_inspect(@time.Period::of(years=1).with_years(2), content="P2Y")
  @debug.debug_inspect(@time.Period::of(years=1).with_years(-1), content="P-1Y")
}

///|
test "with_months" {
  @debug.debug_inspect(@time.Period::of(months=1).with_months(1), content="P1M")
  @debug.debug_inspect(@time.Period::of(months=1).with_months(2), content="P2M")
  @debug.debug_inspect(@time.Period::of(months=1).with_months(-1), content="P-1M")
}

///|
test "with_days" {
  @debug.debug_inspect(@time.Period::of(days=1).with_days(1), content="P1D")
  @debug.debug_inspect(@time.Period::of(days=1).with_days(2), content="P2D")
  @debug.debug_inspect(@time.Period::of(days=1).with_days(-1), content="P-1D")
}

///|
test "op_add" {
  let p1 = @time.Period::of(years=1, months=2, days=3)
  let p2 = @time.Period::of(years=-1, months=-2, days=-3)
  let p3 = @time.Period::of(
    years=@int.MAX_VALUE,
    months=@int.MAX_VALUE,
    days=@int.MAX_VALUE,
  )
  let p4 = @time.Period::of(
    years=@int.MIN_VALUE,
    months=@int.MIN_VALUE,
    days=@int.MIN_VALUE,
  )
  @debug.debug_inspect(p1.op_add(@time.Period::zero()), content="P1Y2M3D")
  @debug.debug_inspect(p1.op_add(p2), content="P0D")
  @debug.debug_inspect(p1.op_add(p1), content="P2Y4M6D")
  @debug.debug_inspect(p2.op_add(p2), content="P-2Y-4M-6D")
  assert_true((try? p1.op_add(p3)) is Err(_))
  assert_true((try? p2.op_add(p4)) is Err(_))
}

///|
test "op_sub" {
  let p1 = @time.Period::of(years=1, months=2, days=3)
  let p2 = @time.Period::of(years=-1, months=-2, days=-3)
  let p3 = @time.Period::of(
    years=@int.MAX_VALUE,
    months=@int.MAX_VALUE,
    days=@int.MAX_VALUE,
  )
  let p4 = @time.Period::of(
    years=@int.MIN_VALUE,
    months=@int.MIN_VALUE,
    days=@int.MIN_VALUE,
  )
  @debug.debug_inspect(p1.op_sub(p1), content="P0D")
  @debug.debug_inspect(p1.op_sub(p2), content="P2Y4M6D")
  @debug.debug_inspect(p2.op_sub(p1), content="P-2Y-4M-6D")
  assert_true((try? p3.op_sub(p2)) is Err(_))
  assert_true((try? p4.op_sub(p1)) is Err(_))
}

///|
test "multiply" {
  let p = @time.Period::of(years=1, months=2, days=3)
  @debug.debug_inspect(p.multiply(0), content="P0D")
  @debug.debug_inspect(p.multiply(1), content="P1Y2M3D")
  @debug.debug_inspect(p.multiply(-1), content="P-1Y-2M-3D")
  @debug.debug_inspect(p.multiply(2), content="P2Y4M6D")
  assert_true((try? p.multiply(@int.MAX_VALUE)) is Err(_))
  assert_true((try? p.multiply(@int.MIN_VALUE)) is Err(_))
}

///|
test "negated" {
  let p = @time.Period::of(years=1, months=1, days=1)
  @debug.debug_inspect(p.negated(), content="P-1Y-1M-1D")
  @debug.debug_inspect(p.negated().negated() == p, content="true")
  let p = @time.Period::of(
    years=@int.MAX_VALUE,
    months=@int.MAX_VALUE,
    days=@int.MAX_VALUE,
  )
  @debug.debug_inspect(p.negated(), content="P-2147483647Y-2147483647M-2147483647D")
  @debug.debug_inspect(p.negated().negated() == p, content="true")
  let p = @time.Period::of(
    years=@int.MIN_VALUE,
    months=@int.MIN_VALUE,
    days=@int.MIN_VALUE,
  )
  assert_true((try? p.negated()) is Err(_))
}
