package main

import "core:fmt"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:mem"
import virtual "core:mem/virtual"
import "core:time"
import ecs "odecs" // Busca la carpeta "odecs" relativa a main.odin

CACHE_LINE_ALIGNMENT :: 64

Neuron :: struct #align(CACHE_LINE_ALIGNMENT) {
	// --- 1. Campos de 32 bits (Offset 0..8) - Alineación 4B ---
	t_last:                 u32,    // Timestamp de último disparo (4B)
	t_prev:                 u32,    // Timestamp de disparo previo (4B)

	// --- 2. Campos de 16 bits (Offset 8..28) - Alineación 2B ---
	v_membrane:             i16,    // Voltaje de membrana (2B)
	v_threshold:            i16,    // Umbral adaptativo (2B)
	histeresis:             i16,    // Histéresis del canal ionizado (2B)
	calcium_trace:          u16,    // Traza de calcio intracelular (2B)
	stp_u:                  u16,    // Tsodyks-Markram u (2B)
	stp_r:                  u16,    // Tsodyks-Markram R (2B)
	bitfield:               u16,    // Flags de estado somático (2B)
	plasticity_fractional:  u16,    // Acumulador estocástico (2B)
	bcm_threshold:          u16,    // Umbral metaplástico BCM (2B)
	prng_seed:              u16,    // Semilla PRNG local (2B)

	// --- 3. Campos de 8 bits individuales (Offset 28..48) - Alineación 1B ---
	refractario:            u8,     // Periodo refractario (1B)
	gating_somatic:         i8,     // SST+ (1B)
	gating_context:         i8,     // VIP+ (1B)
	nmda_latch:             u8,     // Memoria de trabajo local (1B)
	stdp_pre:               u8,     // Traza STDP pre (1B)
	stdp_post:              u8,     // Traza STDP post (1B)
	stdp_triplet:           u8,     // Triplet STDP (1B)
	eligibility_fast:       u8,     // Elegibilidad rápida (1B)
	eligibility_slow:       u8,     // Elegibilidad lenta (1B)
	frequency_homeostasis:  u8,     // Homeostasis de frecuencia (1B)
	axon_delay_exc:         u8,     // Retardo excitador (1B)
	axon_delay_inh:         u8,     // Retardo inhibidor (1B)
	axon_delay_desinh:      u8,     // Retardo desinhibidor (1B)
	stdp_pre_mode:          u8,     // STDP Pre MoDE (1B)
	stdp_post_mode:         u8,     // STDP Post MoDE (1B)
	stdp_post_slow_mode:    u8,     // STDP Post Lenta MoDE (1B)
	homeostasis_mode:       u8,     // Homeostasis expertos (1B)
	stp_tau_fac:            u8,     // Decaimiento facilitación (1B)
	stp_tau_rec:            u8,     // Recuperación depósito (1B)
	stp_u0:                 u8,     // Sensibilidad basal (1B)

	// --- 4. Conexiones y Árbol Dendrítico (Offset 48..192) - 144 Bytes ---
	axons_exc:              [64]u8, // 128 Axones excitadores (64B)
	axons_inh:              [16]u8, // 32 Axones inhibidores (16B)
	axons_desinh:           [4]u8,  // 8 Axones desinhibidores (4B)
	dendrites_sec:          [16]u8, // 16 Dendritas secundarias (16B)
	dendrites_prim:         [8]u8,  // 8 Dendritas primarias (8B)
	gating_dendritic:       [24]u8, // 24 Gating dendrítico (24B)
	dendrites_mode:         [4]u8,  // 4 Dendritas MoDE (4B)
	gating_mode:            [4]u8,  // 4 Gating MoDE (4B)
	routers_som:            [4]u8,  // 4 Enrutadores SOM+ (4B)
}

#assert(size_of(Neuron) == 192, "Error: Neuron debe medir exactamente 192 bytes")
#assert(align_of(Neuron) == CACHE_LINE_ALIGNMENT, "Error: Neuron debe estar alineada a 64 bytes")
