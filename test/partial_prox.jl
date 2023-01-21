# test partial prox feature for operators that implement it
for op ∈ (:NormL0, :NormL1, :RootNormLhalf)
  @testset "shifted $op with box partial prox" begin
    h = eval(op)(3.14)
    n = 5
    l = zeros(n)
    u = ones(n)
    x = rand(n)
    s = rand(n)
    q = rand(n) .- 0.5
    Δ = 0.5
    χ = NormLinf(1.0)

    # compute the prox wrt all variables
    ψ = op == :RootNormLhalf ? shifted(h, x, Δ, χ) : shifted(h, x, l, u)
    if op == :RootNormLhalf
      # redefine l and u temporarily until this operator supports bound constraints
      l .= -Δ
      u .= Δ
    end
    ω = shifted(ψ, s)
    σ = 1.0
    y = prox(ω, q, σ)

    # compute a partial prox
    selected = 1:2:n
    ψ = op == :RootNormLhalf ? shifted(h, x, Δ, χ, selected) : shifted(h, x, l, u, selected)
    ω = shifted(ψ, s)
    σ = 1.0
    z = prox(ω, q, σ)
    p = min.(max.(q, l - s), u - s)

    for i = 1:n
      if i ∈ selected
        @test z[i] == y[i]
      else
        @test z[i] == p[i]
      end
    end

    if op == :NormL0 || op == :NormL1
      d = ones(n) # d = e
      y = iprox(ω, q, d)
      ω = shifted(ψ, s)
      σ = 1.0
      z = iprox(ω, q, d)
      p = min.(max.(q, l - s), u - s)
      for i = 1:n
        if i ∈ selected
          @test z[i] == y[i]
        else
          @test z[i] == p[i]
        end
      end

      d = -ones(n) # d = -e
      y = iprox(ω, q, d)
      ω = shifted(ψ, s)
      z = iprox(ω, q, d)
      p = zeros(n)
      for i=1:n
        p[i] = (abs(u[i] - s[i] - q[i]) < abs(l[i] - s[i] - q[i])) ? (l[i] - s[i]) : (u[i] - s[i])
      end
      for i = 1:n
        if i ∈ selected
          @test z[i] == y[i]
        else
          @test z[i] == p[i]
        end
      end

      d = zeros(n) # d = 0*e
      y = iprox(ω, q, d)
      ω = shifted(ψ, s)
      z = iprox(ω, q, d)
      for i = 1:n
        if i ∈ selected
          @test z[i] == y[i]
        else
          @test z[i] == 0.0
        end
      end
    end
  end
end
