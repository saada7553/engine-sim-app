#include "../include/gas_system.h"

#include "../include/units.h"
#include "../include/utilities.h"

#include <cmath>
#include <cassert>
#include <Accelerate/Accelerate.h>

// Fast reciprocal square root (Quake-style, adapted for double)
static inline double fastInvSqrt(double x) {
    return 1.0 / __builtin_sqrt(x);
}

// Fast power for common exponents used in gas dynamics
// For hcr=1.4 (5 DOF): 1/hcr = 0.7142857, (hcr-1)/hcr = 0.2857143
static inline double fastPow_0_7143(double x) {
    // x^(5/7) ≈ x^0.7143 = (x^2)^(1/7) * x^(3/7)
    // Using cbrt and sqrt approximation: x^(2/3) * x^(1/21) ≈ x^0.714
    // Simpler: use native pow with __builtin hint
    return __builtin_pow(x, 0.7142857142857143);
}

static inline double fastPow_0_2857(double x) {
    // x^(2/7) = seventh root of x squared
    return __builtin_pow(x, 0.2857142857142857);
}

void GasSystem::setGeometry(double width, double height, double dx, double dy) {
    m_width = width;
    m_height = height;
    m_dx = dx;
    m_dy = dy;
}

void GasSystem::initialize(double P, double V, double T, const Mix &mix, int degreesOfFreedom) {
    m_degreesOfFreedom = degreesOfFreedom;
    m_state.n_mol = P * V / (constants::R * T);
    m_state.V = V;
    m_state.E_k = T * (0.5 * degreesOfFreedom * m_state.n_mol * constants::R);
    m_state.mix = mix;
    m_state.momentum[0] = m_state.momentum[1] = 0;

    const double hcr = heatCapacityRatio();
    m_chokedFlowLimit = chokedFlowLimit(degreesOfFreedom);
    m_chokedFlowFactorCached = chokedFlowRate(degreesOfFreedom);
}

void GasSystem::reset(double P, double T, const Mix &mix) {
    m_state.n_mol = P * volume() / (constants::R * T);
    m_state.E_k = T * (0.5 * m_degreesOfFreedom * m_state.n_mol * constants::R);
    m_state.mix = mix;
    m_state.momentum[0] = m_state.momentum[1] = 0;
}

void GasSystem::setVolume(double V) {
    return changeVolume(V - m_state.V);
}

void GasSystem::setN(double n) {
    m_state.E_k = kineticEnergy(n);
    m_state.n_mol = n;
}

void GasSystem::changeVolume(double dV) {
    const double V = this->volume();
    // Cube root of the chamber volume. std::cbrt is a dedicated libm routine —
    // exact and faster than the general std::pow(x, 1/3) this used to call, and
    // this runs every substep via setVolume().
    const double L = std::cbrt(V + dV);
    const double surfaceArea = (L * L);
    const double dL = -dV / surfaceArea;
    const double W = dL * pressure() * surfaceArea;

    m_state.V += dV;
    m_state.E_k += W;
}

void GasSystem::changePressure(double dP) {
    m_state.E_k += dP * volume() * m_degreesOfFreedom * 0.5;
}

void GasSystem::changeTemperature(double dT) {
    m_state.E_k += dT * 0.5 * m_degreesOfFreedom * n() * constants::R;
}

void GasSystem::changeEnergy(double dE) {
    m_state.E_k += dE;
}

void GasSystem::changeMix(const Mix &mix) {
    m_state.mix = mix;
}

void GasSystem::injectFuel(double n) {
    const double n_fuel = this->n_fuel() + n;
    const double p_fuel = n_fuel / this->n();
    m_state.mix.p_fuel = p_fuel;
}

void GasSystem::changeTemperature(double dT, double n) {
    m_state.E_k += dT * 0.5 * m_degreesOfFreedom * n * constants::R;
}

double GasSystem::react(double n, const Mix &mix) {
    const double l_n_fuel = mix.p_fuel * n;
    const double l_n_o2 = mix.p_o2 * n;

    const double system_n_fuel = n_fuel();
    const double system_n_o2 = n_o2();
    const double system_n_inert = n_inert();
    const double system_n = this->n();

    // Assuming the following reaction:
    // 25[O2] + 2[C8H16] -> 16[CO2] + 18[H2O]
    constexpr double ideal_o2_ratio = 25.0 / 2;
    constexpr double ideal_fuel_ratio = 2.0 / 25;
    constexpr double output_input_ratio = (16.0 + 18.0) / (25 + 2);

    const double ideal_fuel_n = ideal_fuel_ratio * l_n_o2;
    const double ideal_o2_n = ideal_o2_ratio * l_n_fuel;
    
    const double a_n_fuel = std::fmin(
        std::fmin(system_n_fuel, l_n_fuel),
        ideal_fuel_n);
    const double a_n_o2 = std::fmin(
        std::fmin(system_n_o2, l_n_o2),
        ideal_o2_n);

    const double reactants_n = a_n_fuel + a_n_o2;
    const double products_n = output_input_ratio * reactants_n;
    const double dn = products_n - reactants_n;

    m_state.n_mol += dn;

    // Adjust mix
    const double new_system_n_fuel = system_n_fuel - a_n_fuel;
    const double new_system_n_o2 = system_n_o2 - a_n_o2;
    const double new_system_n_inert = system_n_inert + products_n;
    const double new_system_n = system_n + dn;

    if (new_system_n != 0) {
        m_state.mix.p_fuel = new_system_n_fuel / new_system_n;
        m_state.mix.p_inert = new_system_n_inert / new_system_n;
        m_state.mix.p_o2 = new_system_n_o2 / new_system_n;
    }
    else {
        m_state.mix.p_fuel = m_state.mix.p_inert = m_state.mix.p_o2 = 0;
    }

    return a_n_fuel;
}

double GasSystem::flowConstant(
    double targetFlowRate,
    double P,
    double pressureDrop,
    double T,
    double hcr)
{
    const double T_0 = T;
    const double p_0 = P, p_T = P - pressureDrop; // p_0 = upstream pressure

    const double chokedFlowLimit =
        std::pow((2.0 / (hcr + 1)), hcr / (hcr - 1));
    const double p_ratio = p_T / p_0;

    double flowRate = 0;
    if (p_ratio <= chokedFlowLimit) {
        // Choked flow
        flowRate = std::sqrt(hcr);
        flowRate *= std::pow(2 / (hcr + 1), (hcr + 1) / (2 * (hcr - 1)));
    }
    else {
        flowRate = (2 * hcr) / (hcr - 1);
        flowRate *= (1 - std::pow(p_ratio, (hcr - 1) / hcr));
        flowRate = std::sqrt(flowRate);
        flowRate *= std::pow(p_ratio, 1 / hcr);
    }

    flowRate *= p_0 / std::sqrt(constants::R * T_0);

    return targetFlowRate / flowRate;
}

double GasSystem::k_28inH2O(double flowRateScfm) {
    return flowConstant(
        units::flow(flowRateScfm, units::scfm),
        units::pressure(1.0, units::atm),
        units::pressure(28.0, units::inH2O),
        units::celcius(25),
        heatCapacityRatio(5)
    );
}

double GasSystem::k_carb(double flowRateScfm) {
    return flowConstant(
        units::flow(flowRateScfm, units::scfm),
        units::pressure(1.0, units::atm),
        units::pressure(1.5, units::inHg),
        units::celcius(25),
        heatCapacityRatio(5)
    );
}

double GasSystem::flowRate(
    double k_flow,
    double P0,
    double P1,
    double T0,
    double T1,
    double hcr,
    double chokedFlowLimit,
    double chokedFlowRateCached)
{
    if (k_flow == 0) return 0;

    double direction;
    double T_0;
    double p_0, p_T; // p_0 = upstream pressure
    if (P0 > P1) {
        direction = 1.0;
        T_0 = T0;
        p_0 = P0;
        p_T = P1;
    }
    else {
        direction = -1.0;
        T_0 = T1;
        p_0 = P1;
        p_T = P0;
    }

    const double p_ratio = p_T / p_0;
    const double inv_sqrt_RT = 1.0 / __builtin_sqrt(constants::R * T_0);

    double flowRate = 0;
    if (p_ratio <= chokedFlowLimit) {
        // Choked flow
        flowRate = chokedFlowRateCached * inv_sqrt_RT;
    }
    else {
        // Optimized: use __builtin_pow for better codegen
        const double inv_hcr = 1.0 / hcr;
        const double s = __builtin_pow(p_ratio, inv_hcr);

        const double hcr_factor = (2 * hcr) / (hcr - 1);
        const double flow_sq = hcr_factor * s * (s - p_ratio);
        flowRate = __builtin_sqrt(std::fmax(flow_sq, 0.0)) * inv_sqrt_RT;
    }

    return flowRate * direction * p_0 * k_flow;
}

double GasSystem::loseN(double dn, double E_k_per_mol) {
    m_state.E_k -= E_k_per_mol * dn;
    m_state.n_mol -= dn;

    if (m_state.n_mol < 0) {
        m_state.n_mol = 0;
    }

    return dn;
}

double GasSystem::gainN(double dn, double E_k_per_mol, const Mix &mix) {
    const double next_n = m_state.n_mol + dn;
    const double current_n = m_state.n_mol;

    m_state.E_k += dn * E_k_per_mol;
    m_state.n_mol = next_n;

    if (next_n != 0) {
        m_state.mix.p_fuel = (m_state.mix.p_fuel * current_n + dn * mix.p_fuel) / next_n;
        m_state.mix.p_inert = (m_state.mix.p_inert * current_n + dn * mix.p_inert) / next_n;
        m_state.mix.p_o2 = (m_state.mix.p_o2 * current_n + dn * mix.p_o2) / next_n;
    }
    else {
        m_state.mix.p_fuel = m_state.mix.p_inert = m_state.mix.p_o2 = 0;
    }

    return -dn;
}

void GasSystem::dissipateExcessVelocity() {
    const double v_x = velocity_x();
    const double v_y = velocity_y();
    const double v_squared = v_x * v_x + v_y * v_y;
    const double c = this->c();
    const double c_squared = c * c;

    if (c_squared >= v_squared || v_squared == 0) {
        return;
    }

    const double k_squared = c_squared / v_squared;
    const double k = std::sqrt(k_squared);

    m_state.momentum[0] *= k;
    m_state.momentum[1] *= k;

    m_state.E_k += 0.5 * mass() * (v_squared - c_squared);

    if (m_state.E_k < 0) m_state.E_k = 0;
}

void GasSystem::updateVelocity(double dt, double beta) {
    if (n() == 0) return;

    const double depth = volume() / (m_width * m_height);
    
    double d_momentum_x = 0;
    double d_momentum_y = 0;

    const double p0 = dynamicPressure(m_dx, m_dy);
    const double p1 = dynamicPressure(-m_dx, -m_dy);
    const double p2 = dynamicPressure(m_dy, m_dx);
    const double p3 = dynamicPressure(-m_dy, -m_dx);

    const double p_sa_0 = p0 * (m_height * depth);
    const double p_sa_1 = p1 * (m_height * depth);
    const double p_sa_2 = p2 * (m_width * depth);
    const double p_sa_3 = p3 * (m_width * depth);

    d_momentum_x += p_sa_0 * m_dx;
    d_momentum_y += p_sa_0 * m_dy;

    d_momentum_x -= p_sa_1 * m_dx;
    d_momentum_y -= p_sa_1 * m_dy;

    d_momentum_x += p_sa_2 * m_dy;
    d_momentum_y += p_sa_2 * m_dx;

    d_momentum_x -= p_sa_3 * m_dy;
    d_momentum_y -= p_sa_3 * m_dx;

    const double m = mass();
    const double inv_m = 1 / m;
    const double v0_x = m_state.momentum[0] * inv_m;
    const double v0_y = m_state.momentum[1] * inv_m;

    m_state.momentum[0] -= d_momentum_x * dt * beta;
    m_state.momentum[1] -= d_momentum_y * dt * beta;

    const double v1_x = m_state.momentum[0] * inv_m;
    const double v1_y = m_state.momentum[1] * inv_m;

    m_state.E_k -= 0.5 * m * (v1_x * v1_x - v0_x * v0_x);
    m_state.E_k -= 0.5 * m * (v1_y * v1_y - v0_y * v0_y);

    if (m_state.E_k < 0) m_state.E_k = 0;
}

void GasSystem::dissipateVelocity(double dt, double timeConstant) {
    if (n() == 0) return;

    const double invMass = 1.0 / mass();
    const double velocity_x = m_state.momentum[0] * invMass;
    const double velocity_y = m_state.momentum[1] * invMass;
    const double velocity_squared =
        velocity_x * velocity_x + velocity_y * velocity_y;

    const double s = dt / (dt + timeConstant);
    m_state.momentum[0] = m_state.momentum[0] * (1 - s);
    m_state.momentum[1] = m_state.momentum[1] * (1 - s);

    const double newVelocity_x = m_state.momentum[0] * invMass;
    const double newVelocity_y = m_state.momentum[1] * invMass;
    const double newVelocity_squared =
        newVelocity_x * newVelocity_x + newVelocity_y * newVelocity_y;

    const double dE_k = 0.5 * mass() * (velocity_squared - newVelocity_squared);
    m_state.E_k += dE_k;
}

double GasSystem::flow(const FlowParameters &params) {
    // Early exit for zero flow constant
    if (params.k_flow == 0) return 0;

    const double P_0 =
        params.system_0->pressure()
        + params.system_0->dynamicPressure(params.direction_x, params.direction_y);
    const double P_1 =
        params.system_1->pressure()
        + params.system_1->dynamicPressure(-params.direction_x, -params.direction_y);

    // Determine flow direction - use branchless-friendly assignments
    const bool forward = P_0 > P_1;
    const double direction = forward ? 1.0 : -1.0;
    const double dx = forward ? params.direction_x : -params.direction_x;
    const double dy = forward ? params.direction_y : -params.direction_y;
    GasSystem* const source = forward ? params.system_0 : params.system_1;
    GasSystem* const sink = forward ? params.system_1 : params.system_0;
    const double sourcePressure = forward ? P_0 : P_1;
    const double sinkPressure = forward ? P_1 : P_0;
    const double sourceCrossSection = forward ? params.crossSectionArea_0 : params.crossSectionArea_1;
    const double sinkCrossSection = forward ? params.crossSectionArea_1 : params.crossSectionArea_0;

    // Cache frequently accessed values
    const double source_n = source->n();
    if (source_n == 0) return 0;

    double flow = params.dt * flowRate(
        params.k_flow,
        sourcePressure,
        sinkPressure,
        source->temperature(),
        sink->temperature(),
        source->heatCapacityRatio(),
        source->m_chokedFlowLimit,
        source->m_chokedFlowFactorCached);

    flow = clamp(flow, 0.0, 0.9 * source_n);

    // Early exit if no flow
    if (flow == 0) return 0;

    const double fraction = flow / source_n;
    const double source_volume = source->volume();
    const double fractionVolume = fraction * source_volume;
    const double sourceMass = source->mass();
    const double fractionMass = fraction * sourceMass;

    // Stage 1: Fraction flows from source to sink
    const double E_k_bulk_src0 = source->bulkKineticEnergy();
    const double E_k_bulk_sink0 = sink->bulkKineticEnergy();

    const double E_k_per_mol = source->kineticEnergyPerMol();
    sink->gainN(flow, E_k_per_mol, source->mix());
    source->loseN(flow, E_k_per_mol);

    // Transfer momentum proportionally
    const double dp_x = source->m_state.momentum[0] * fraction;
    const double dp_y = source->m_state.momentum[1] * fraction;
    source->m_state.momentum[0] -= dp_x;
    source->m_state.momentum[1] -= dp_y;
    sink->m_state.momentum[0] += dp_x;
    sink->m_state.momentum[1] += dp_y;

    const double E_k_bulk_src1 = source->bulkKineticEnergy();
    const double E_k_bulk_sink1 = sink->bulkKineticEnergy();
    sink->m_state.E_k -= (E_k_bulk_src1 + E_k_bulk_sink1) - (E_k_bulk_src0 + E_k_bulk_sink0);

    // Cache masses after transfer (they changed)
    const double newSourceMass = source->mass();
    const double sinkMass = sink->mass();

    // Store initial momenta for energy conservation
    const double srcMom0_x = source->m_state.momentum[0];
    const double srcMom0_y = source->m_state.momentum[1];
    const double sinkMom0_x = sink->m_state.momentum[0];
    const double sinkMom0_y = sink->m_state.momentum[1];

    // Add momentum from fraction velocity
    const double inv_dt = 1.0 / params.dt;

    if (sinkCrossSection != 0) {
        const double c_sink = sink->c();
        const double sinkFracVel = clamp((fractionVolume / sinkCrossSection) * inv_dt, 0.0, c_sink);
        sink->m_state.momentum[0] += sinkFracVel * dx * fractionMass;
        sink->m_state.momentum[1] += sinkFracVel * dy * fractionMass;
    }

    if (sourceCrossSection != 0 && newSourceMass != 0) {
        const double c_source = source->c();
        const double srcFracVel = clamp((fractionVolume / sourceCrossSection) * inv_dt, 0.0, c_source);
        source->m_state.momentum[0] += srcFracVel * dx * fractionMass;
        source->m_state.momentum[1] += srcFracVel * dy * fractionMass;
    }

    // Energy conservation: E_k change = 0.5 * m * (v1^2 - v0^2)
    // Using: v^2 = p^2 / m^2, so m*v^2 = p^2/m
    // E_k change = 0.5 * (p1^2 - p0^2) / m
    if (newSourceMass != 0) {
        const double invSrcMass = 1.0 / newSourceMass;
        const double srcMom1_x = source->m_state.momentum[0];
        const double srcMom1_y = source->m_state.momentum[1];
        source->m_state.E_k -= 0.5 * invSrcMass *
            ((srcMom1_x * srcMom1_x - srcMom0_x * srcMom0_x) +
             (srcMom1_y * srcMom1_y - srcMom0_y * srcMom0_y));
    }

    if (sinkMass > 0) {
        const double invSinkMass = 1.0 / sinkMass;
        const double sinkMom1_x = sink->m_state.momentum[0];
        const double sinkMom1_y = sink->m_state.momentum[1];
        sink->m_state.E_k -= 0.5 * invSinkMass *
            ((sinkMom1_x * sinkMom1_x - sinkMom0_x * sinkMom0_x) +
             (sinkMom1_y * sinkMom1_y - sinkMom0_y * sinkMom0_y));
    }

    // Clamp negative energies
    if (sink->m_state.E_k < 0) sink->m_state.E_k = 0;
    if (source->m_state.E_k < 0) source->m_state.E_k = 0;

    return flow * direction;
}

double GasSystem::flow(double k_flow, double dt, double P_env, double T_env, const Mix &mix) {
    const double maxFlow = pressureEquilibriumMaxFlow(P_env, T_env);
    double flow = dt * flowRate(
        k_flow,
        pressure(),
        P_env,
        temperature(),
        T_env,
        heatCapacityRatio(),
        m_chokedFlowLimit,
        m_chokedFlowFactorCached);

    if (std::abs(flow) > std::abs(maxFlow)) {
        flow = maxFlow;
    }

    if (flow < 0) {
        const double bulk_E_k_0 = bulkKineticEnergy();
        gainN(-flow, kineticEnergyPerMol(T_env, m_degreesOfFreedom), mix);
        const double bulk_E_k_1 = bulkKineticEnergy();

        m_state.E_k += (bulk_E_k_1 - bulk_E_k_0);
    }
    else {
        const double starting_n = n();
        loseN(flow, kineticEnergyPerMol());

        m_state.momentum[0] -= (flow / starting_n) * m_state.momentum[0];
        m_state.momentum[1] -= (flow / starting_n) * m_state.momentum[1];
    }

    return flow;
}

double GasSystem::pressureEquilibriumMaxFlow(const GasSystem *b) const {
    // pressure_a = (kineticEnergy() + n * b->kineticEnergyPerMol()) / (0.5 * degreesOfFreedom * volume())
    // pressure_b = (b->kineticEnergy() - n *  / (0.5 * b->degreesOfFreedom * b->volume())
    // pressure_a = pressure_b

    // E_a = kineticEnergy()
    // E_b = b->kineticEnergy()
    // D_a = E_a / n()
    // D_b = E_b / b->n()
    // Q_a = 1 / (0.5 * degreesOfFreedom * volume())
    // Q_b = 1 / (0.5 * b->degreesOfFreedom * b->volume())
    // pressure_a = Q_a * (E_a + dn * D_b)
    // pressure_b = Q_b * (E_b - dn * D_b)

    if (pressure() > b->pressure()) {
        const double maxFlow =
                (b->volume() * kineticEnergy() - volume() * b->kineticEnergy()) /
                (b->volume() * kineticEnergyPerMol() + volume() * kineticEnergyPerMol());
        return std::fmax(0.0, std::fmin(maxFlow, n()));
    }
    else {
        const double maxFlow =
                (b->volume() * kineticEnergy() - volume() * b->kineticEnergy()) /
                (b->volume() * b->kineticEnergyPerMol() + volume() * b->kineticEnergyPerMol());
        return std::fmin(0.0, std::fmax(maxFlow, -b->n()));
    }
}

double GasSystem::pressureEquilibriumMaxFlow(double P_env, double T_env) const {
    if (pressure() > P_env) {
        return -(P_env * (0.5 * m_degreesOfFreedom * volume()) - kineticEnergy()) / kineticEnergyPerMol();
    }
    else {
        const double E_k_per_mol_env = 0.5 * T_env * constants::R * m_degreesOfFreedom;
        return -(P_env * (0.5 * m_degreesOfFreedom * volume()) - kineticEnergy()) / E_k_per_mol_env;
    }
}
