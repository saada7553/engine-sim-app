#include "../include/vehicle_drag_constraint.h"

#include "../include/constants.h"
#include "../include/units.h"
#include "../include/vehicle.h"

VehicleDragConstraint::VehicleDragConstraint() : Constraint(1, 1) {
    m_ks = 10.0;
    m_kd = 1.0;

    m_vehicle = nullptr;
}

VehicleDragConstraint::~VehicleDragConstraint() {
    /* void */
}

void VehicleDragConstraint::initialize(atg_scs::RigidBody *rotatingMass, Vehicle *vehicle) {
    m_bodies[0] = rotatingMass;
    m_vehicle = vehicle;
}

void VehicleDragConstraint::calculate(Output *output, atg_scs::SystemState *system) {
    output->C[0] = 0;

    output->J[0][0] = 0.0;
    output->J[0][1] = 0.0;
    output->J[0][2] = -1.0;

    output->J[0][3] = 0.0;
    output->J[0][4] = 0.0;
    output->J[0][5] = 1.0;

    output->J_dot[0][0] = 0;
    output->J_dot[0][1] = 0;
    output->J_dot[0][2] = 0;

    output->J_dot[0][3] = 0;
    output->J_dot[0][4] = 0;
    output->J_dot[0][5] = 0;

    output->kd[0] = m_kd;
    output->ks[0] = m_ks;

    output->v_bias[0] = 0;

    constexpr double airDensity =
        units::AirMolecularMass * units::pressure(1.0, units::atm)
        / (constants::R * units::celcius(25.0));
    const double v = m_vehicle->getSpeed();
    const double v_squared = v * v;
    const double c_d = m_vehicle->getDragCoefficient();
    const double A = m_vehicle->getCrossSectionArea();
    const double rollingResistance = m_vehicle->getRollingResistance();
    // The brake joins drag and rolling resistance in this single resistive
    // torque. They are one bundle, so they always engage and disengage together.
    const double brakeForce = m_vehicle->getBrakeForce();

    const double maxResistiveTorque = m_vehicle->linearForceToVirtualTorque(
        rollingResistance + brakeForce + 0.5 * airDensity * v_squared * c_d * A);

    // Resistance must oppose the wheel mass's CURRENT direction of rotation, so
    // pick the limit side from the live sign of v_theta. getSpeed() squares the
    // velocity and can't tell us the sign, hence reading the body directly. The
    // solver applies a torque of -lambda to v_theta: a forward car (v_theta < 0)
    // needs a positive torque, so lambda opens negative; a reversed one needs a
    // negative torque, so lambda opens positive. Anchoring the limit to one side
    // turned v = 0 into an unstable point: once v_theta crossed to the wrong
    // sign, drag and brake became an accelerating force with no path back, so
    // the car ran away and ignored all resistance until the vehicle was reset.
    const double wheelSpeed = m_bodies[0]->v_theta;
    if (wheelSpeed > 0.0) {
        output->limits[0][0] = 0;
        output->limits[0][1] = maxResistiveTorque;
    } else {
        output->limits[0][0] = -maxResistiveTorque;
        output->limits[0][1] = 0;
    }
}
