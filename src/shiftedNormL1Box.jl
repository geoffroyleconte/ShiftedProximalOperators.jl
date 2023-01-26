export ShiftedNormL1Box

mutable struct ShiftedNormL1Box{
  R <: Real,
  T <: Integer,
  V0 <: AbstractVector{R},
  V1 <: AbstractVector{R},
  V2 <: AbstractVector{R},
  V3,
  V4,
} <: ShiftedProximableFunction
  h::NormL1{R}
  xk::V0
  sj::V1
  sol::V2
  l::V3
  u::V4
  shifted_twice::Bool
  selected::AbstractArray{T}

  function ShiftedNormL1Box(
    h::NormL1{R},
    xk::AbstractVector{R},
    sj::AbstractVector{R},
    l,
    u,
    shifted_twice::Bool,
    selected::AbstractArray{T},
  ) where {R <: Real, T <: Integer}
    sol = similar(xk)
    if any(l .> u)
      error("Error: at least one lower bound is greater than the upper bound.")
    end
    new{R, T, typeof(xk), typeof(sj), typeof(sol), typeof(l), typeof(u)}(
      h,
      xk,
      sj,
      sol,
      l,
      u,
      shifted_twice,
      selected,
    )
  end
end

shifted(
  h::NormL1{R},
  xk::AbstractVector{R},
  l,
  u,
  selected::AbstractArray{T} = 1:length(xk),
) where {R <: Real, T <: Integer} = ShiftedNormL1Box(h, xk, zero(xk), l, u, false, selected)
shifted(
  h::NormL1{R},
  xk::AbstractVector{R},
  Δ::R,
  χ::Conjugate{IndBallL1{R}},
  selected::AbstractArray{T} = 1:length(xk),
) where {R <: Real, T <: Integer} = ShiftedNormL1Box(h, xk, zero(xk), -Δ, Δ, false, selected)
shifted(
  ψ::ShiftedNormL1Box{R, T, V0, V1, V2, V3, V4},
  sj::AbstractVector{R},
) where {
  R <: Real,
  T <: Integer,
  V0 <: AbstractVector{R},
  V1 <: AbstractVector{R},
  V2 <: AbstractVector{R},
  V3,
  V4,
} = ShiftedNormL1Box(ψ.h, ψ.xk, sj, ψ.l, ψ.u, true, ψ.selected)

function (ψ::ShiftedNormL1Box)(y)
  val = ψ.h((ψ.xk + ψ.sj + y)[ψ.selected])
  ϵ = √eps(eltype(y))
  for i ∈ eachindex(y)
    lower = typeof(ψ.l) <: Real ? ψ.l : ψ.l[i]
    upper = typeof(ψ.u) <: Real ? ψ.u : ψ.u[i]
    if !(lower - ϵ ≤ ψ.sj[i] + y[i] ≤ upper + ϵ)
      return Inf
    end
  end
  return val
end

fun_name(ψ::ShiftedNormL1Box) = "shifted L1 norm with box indicator"
fun_expr(ψ::ShiftedNormL1Box) = "t ↦ ‖xk + sj + t‖₁ + χ({sj + t .∈ [l,u]})"
fun_params(ψ::ShiftedNormL1Box) =
  "xk = $(ψ.xk)\n" * " "^14 * "sj = $(ψ.sj)\n" * " "^14 * "l = $(ψ.l)\n" * " "^14 * "u = $(ψ.u)"

# solve i-th subproblem of the proximal operator
function solve_ith_subproblem_proxL1(li::R, ui::R, si::R, qi::R, xs::R, xsq::R, ci::R) where {R <: Real}
  yi = if xsq ≤ -ci
    qi + ci
  elseif xsq ≥ ci
    qi - ci
  else
    -xs
  end
  yi = min(max(yi, li - si), ui - si)
  return yi
end

function prox!(
  y::AbstractVector{R},
  ψ::ShiftedNormL1Box{R, T, V0, V1, V2, V3, V4},
  q::AbstractVector{R},
  σ::R,
) where {
  R <: Real,
  T <: Integer,
  V0 <: AbstractVector{R},
  V1 <: AbstractVector{R},
  V2 <: AbstractVector{R},
  V3,
  V4,
}
  σλ = σ * ψ.λ

  for i ∈ eachindex(y)
    li = isa(ψ.l, Real) ? ψ.l : ψ.l[i]
    ui = isa(ψ.u, Real) ? ψ.u : ψ.u[i]

    qi = q[i]
    si = ψ.sj[i]

    if i ∈ ψ.selected
      xi = ψ.xk[i]
      xs = xi + si
      xsq = xs + qi
      y[i] = solve_ith_subproblem_proxL1(li, ui, si, qi, xs, xsq, σλ)
    else # min ½ σ⁻¹ (y - qi)² subject to li-si ≤ y ≤ ui-si
      y[i] = prox_zero(qi, li - si, ui - si)
    end
  end
  return y
end

function solve_ith_subproblem_iproxL1_neg(li::R, ui::R, xi::R, si::R, sq::R, xs::R, xsq::R, ci::R) where {R <: Real}
  # yi = arg max (yi - qi)^2 + ci|xi + si + yi| - χ(si + yi | [li, ui])
  # where ci < 0 (ci = 2λ / di)
  # possible maxima locations:
  # yi = li - si
  # yi = ui - si
  # yi = -xi - si, if: li + xi ≤ 0 ≤ ui + xi, leads to h(xi + si + yi) = 0
  val_left = (li - sq)^2 + ci * abs(xi + li) # left: yi = li - si
  val_right = (ui - sq)^2 + ci * abs(xi + ui) # right: yi = ui - si
  yi = val_left > val_right ? (li - si) : (ui - si)
  val_max = max(val_left, val_right)
  if (li ≤ -xi ≤ ui)
    val_0 = xsq^2
    (val_0 > val_max) && (yi = -xs)
  end
  return yi
end

function iprox!(
  y::AbstractVector{R},
  ψ::ShiftedNormL1Box{R, T, V0, V1, V2, V3, V4},
  q::AbstractVector{R},
  d::AbstractVector{R},
) where {
  R <: Real,
  T <: Integer,
  V0 <: AbstractVector{R},
  V1 <: AbstractVector{R},
  V2 <: AbstractVector{R},
  V3,
  V4,
}

  λ = ψ.λ
  λ2 = 2 * λ

  for i ∈ eachindex(y)
    li = isa(ψ.l, Real) ? ψ.l : ψ.l[i]
    ui = isa(ψ.u, Real) ? ψ.u : ψ.u[i]

    qi = q[i]
    si = ψ.sj[i]
    di = d[i]
    sq = si + qi

    if i ∈ ψ.selected
      xi = ψ.xk[i]
      xs = xi + si
      xsq = xs + qi

      if di > eps(R)
        ci = λ / di
        y[i] = solve_ith_subproblem_proxL1(li, ui, si, qi, xs, xsq, ci)
      elseif di < -eps(R)
        # yi = arg max (yi - qi)^2 + 2λ|xi + si + yi| / di - χ(si + yi | [li, ui])
        ci = λ2 / di
        y[i] = solve_ith_subproblem_iproxL1_neg(li, ui, xi, si, sq, xs, xsq, ci)
      else # abs(di) < eps(R) , (we consider di = 0)
        y[i] = prox_zero(-xs, li - si, ui - si)
      end 

    else # min ½ di (y - qi)² subject to li-si ≤ y ≤ ui-si
      if di > eps(R)
        y[i] = prox_zero(qi, li - si, ui - si)
      elseif di < -eps(R)
        y[i] = negative_prox_zero(qi, li - si, ui - si)
      else
        y[i] = zero(R)
      end
    end
  end
  return y
end

function iprox!(
  y::AbstractVector{R},
  ψ::ShiftedNormL1Box{R, T, V0, V1, V2, V3, V4},
  q::AbstractVector{R},
  d::R,
) where {
  R <: Real,
  T <: Integer,
  V0 <: AbstractVector{R},
  V1 <: AbstractVector{R},
  V2 <: AbstractVector{R},
  V3,
  V4,
}

  if d > eps(R)
    prox!(y, ψ, q, d)
  elseif d < -eps(R)
    c = 2 * ψ.λ / d
    for i ∈ eachindex(y)
      li = isa(ψ.l, Real) ? ψ.l : ψ.l[i]
      ui = isa(ψ.u, Real) ? ψ.u : ψ.u[i]
      qi = q[i]
      si = ψ.sj[i]
      sq = si + qi
      if i ∈ ψ.selected
        # yi = arg max (yi - qi)^2 + 2λ|xi + si + yi| / d - χ(si + yi | [li, ui])
        xi = ψ.xk[i]
        xs = xi + si
        xsq = xs + qi
        y[i] = solve_ith_subproblem_iproxL1_neg(li, ui, xi, si, sq, xs, xsq, c)
      else # min ½ di (y - qi)² subject to li-si ≤ y ≤ ui-si
        y[i] = negative_prox_zero(qi, li - si, ui - si)
      end
    end
  else # abs(di) < eps(R) (consider di = 0 in this case)
    for i ∈ eachindex(y)
      li = isa(ψ.l, Real) ? ψ.l : ψ.l[i]
      ui = isa(ψ.u, Real) ? ψ.u : ψ.u[i]
      si = ψ.sj[i]
      if i ∈ ψ.selected
        xi = ψ.xk[i]
        xs = xi + si
        y[i] = prox_zero(-xs, li - si, ui - si)
      else # min 0 subject to li-si ≤ y ≤ ui-si
        y[i] = zero(R)
      end
    end
  end

  return y
end
