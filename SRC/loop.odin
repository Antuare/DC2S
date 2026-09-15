package main

import "core:fmt"

// Constantes físicas del paso temporal (100 Hz = 10 ms por tick)
REFRACTORY_DURATION :: 2    // Ticks que la neurona se queda en reposo absoluto
MAX_INT4_WEIGHT     :: 15   // Peso máximo en 4 bits (22% del umbral 68)
NMDA_BOOST_VALUE    :: 34   // Salto supralineal al 50% ante coincidencia

// Helper para extraer un peso de 4 bits (Nibble) de un array empaquetado
get_int4_weight :: #force_inline proc(weights: []u8, index: int) -> i16 {
	byte_val := weights[index / 2]
	if index % 2 == 0 {
		return i16(byte_val & 0x0F)        // Nibble bajo (0 .. 15)
	} else {
		return i16((byte_val >> 4) & 0x0F) // Nibble alto (0 .. 15)
	}
}

// =============================================================================
// MOTOR FÍSICO: Un paso temporal completo (1 Tick de 10 ms)
// =============================================================================
step_network :: proc(net: ^Network) {
	net.current_tick += 1

	// Buffer para recolectar las neuronas que disparen en este tick
	next_active := make([dynamic]int, 0, cap(net.active_indices))

	// =========================================================================
	// FASE 1: PROPAGACIÓN AXONAL (La Ola viaja a través del espacio 3D)
	// =========================================================================
	// Las neuronas que dispararon en el tick anterior propagan su descarga
	// hacia sus 8 vecinos espaciales calculados por grid.odin
	for firing_idx in net.active_indices {
		n := &net.neurons[firing_idx]

		// 1. Fuerza efectiva de salida modulada por la STP (Tsodyks-Markram)
		// Si R está agotado, la señal se atenúa; si u es alto, sale en ráfaga
		stp_factor := (u32(n.stp_u) * u32(n.stp_r)) / 65535 // Escala de 0 a 65535

		// 2. Obtener los 8 vecinos espaciales en 3D (con paredes concretas)
		neighbors := get_3d_neighbors(firing_idx)

		// 3. Descargar energía hacia los vecinos válidos
		for k in 0..<8 {
			target_idx := neighbors[k]

			// Si choca contra una pared concreta (-1), la energía se disipa en la roca
			if target_idx == -1 do continue

			target := &net.neurons[target_idx]

			// Extraemos el peso INT4 de la sinapsis (0 a 15)
			weight := get_int4_weight(n.axons_exc[:], k)

			// Impulso modulado por la STP que llega a la cabeza dendrítica
			transmitted_signal := u8((u32(weight) * stp_factor) / 65535)

			// Se deposita en la dendrita secundaria receptora
			target.dendrites_sec[k] = max(target.dendrites_sec[k], transmitted_signal)
		}
	}

	// =========================================================================
	// FASE 2: VIP+ / SST+ Y CONFIGURACIÓN DINÁMICA MoDE
	// =========================================================================
	for idx in net.active_indices {
		n := &net.neurons[idx]

		// Si VIP+ está activo por atención Top-Down, desinhibe las compuertas SST+
		if n.gating_context > 0 {
			n.gating_somatic = 0
		}

		// Si el camino está abierto, configurar los 4 enrutadores MoDE (Ola 2)
		if n.gating_somatic == 0 {
			for m in 0..<4 {
				n.routers_som[m] = n.gating_mode[m]
			}
		}
	}

	// =========================================================================
	// FASE 3: ÁRBOL DENDRÍTICO (32:16:8) -> INTEGRACIÓN SOMÁTICA
	// =========================================================================
	// Las 16 dendritas secundarias convergen en 8 primarias con boost NMDA
	for i in 0..<net.total_neurons {
		n := &net.neurons[i]

		dendritic_current: i16 = 0
		has_signal := false

		for p in 0..<8 {
			sec_a := i16(n.dendrites_sec[p * 2])
			sec_b := i16(n.dendrites_sec[p * 2 + 1])

			if sec_a == 0 && sec_b == 0 do continue

			has_signal = true
			primary_input: i16 = 0

			// Coincidencia supralineal: dos espigas simultáneas pegan el salto al 50%
			if sec_a > 0 && sec_b > 0 {
				primary_input = NMDA_BOOST_VALUE // Salto a 34 (NMDA boost)
			} else {
				primary_input = max(sec_a, sec_b) // Una espiga sola pasa tal cual
			}

			// Modulación por compuerta dendrítica
			if n.gating_dendritic[p] > 0 {
				n.dendrites_prim[p] = u8(clamp(primary_input, 0, 255))
				dendritic_current += primary_input
			}

			// Limpieza de las cabezas receptoras para el siguiente tick
			n.dendrites_sec[p * 2]     = 0
			n.dendrites_sec[p * 2 + 1] = 0
		}

		// Memoria de trabajo local (NMDA Latch)
		if dendritic_current >= NMDA_BOOST_VALUE {
			n.nmda_latch = 3 // Retención activa por 3 ticks
		} else if n.nmda_latch > 0 {
			dendritic_current += 15 // Inyección sostenida de corriente
			n.nmda_latch -= 1
		}

		// Inyección final de corriente hacia el Soma
		if has_signal || dendritic_current > 0 {
			n.v_membrane += dendritic_current
		}
	}

	// =========================================================================
	// FASE 4: EVALUACIÓN SOMÁTICA (ALIF + H), DISPARO Y SOFT RESET
	// =========================================================================
	for i in 0..<net.total_neurons {
		n := &net.neurons[i]

		// 1. Control del Período Refractario (el diodo de dirección)
		if n.refractario > 0 {
			n.refractario -= 1
			continue // No puede disparar mientras esté en refractario
		}

		// 2. Condición de Disparo: Vm + Histéresis >= Umbral
		if (n.v_membrane + n.histeresis) >= n.v_threshold {
			// ¡DISPARO DE ACCIÓN! Pasa al buffer del siguiente tick
			append(&next_active, i)

			// Soft Reset estilo Mamba (conserva el residuo continuo)
			n.v_membrane -= n.v_threshold

			// Activar período refractario
			n.refractario = REFRACTORY_DURATION

			// La Ola 1 ioniza el canal: H sube para facilitar el paso del siguiente trueno
			n.histeresis = clamp(n.histeresis + 10, 0, 1000)

			// Registrar timestamps para cálculo del ISI
			n.t_prev = n.t_last
			n.t_last = net.current_tick

			// Actualización activa de STP en disparo (u sube, R baja)
			u_jump := u32(n.stp_u0) * (65535 - u32(n.stp_u)) / 255
			n.stp_u = u16(clamp(u32(n.stp_u) + u_jump, 0, 65535))

			r_used := (u32(n.stp_u) * u32(n.stp_r)) / 65535
			n.stp_r = u16(clamp(u32(n.stp_r) - r_used, 0, 65535))

			// Trazas STDP
			n.stdp_post = 255
			n.eligibility_fast = 255

		} else {
			// Si no disparó, recuperación pasiva de STP (R se rellena hacia 65535)
			if n.stp_r < 65535 {
				n.stp_r += u16((65535 - u32(n.stp_r)) / u32(n.stp_tau_rec + 1))
			}
		}
	}

	// =========================================================================
	// FASE 5: ROTACIÓN SEGURA DE BUFFERS (Cero fugas de memoria)
	// =========================================================================
	old_active := net.active_indices
	net.active_indices = next_active
	delete(old_active)
}
