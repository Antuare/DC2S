package main

import "core:fmt"
import "core:mem"

CACHE_LINE_ALIGNMENT :: 64

// [Struct Of a Neuron] — 
Neuron :: struct #packed #align(CACHE_LINE_ALIGNMENT) {
	// --- 1. Soma & ALIF Dynamic State (7 Bytes) ---
	v_membrane:             i16,    // Voltaje de membrana (2B)
	v_threshold:            i16,    // Umbral adaptativo (2B)
	histeresis:             i16,    // Histéresis del canal ionizado (2B)
	refractario:            u8,     // Periodo refractario / Diodo de dirección (1B)

	// --- 2. Interneuronas Parasitarias (2 Bytes) ---
	gating_somatic:         i8,     // SST+ (Gating somático) (1B)
	gating_context:         i8,     // VIP+ (Gating de contexto) (1B)

	// --- 3. Información del Soma (20 Bytes) ---
	nmda_latch:             u8,     // Memoria de trabajo local (1B)
	t_last:                 u32,    // Timestamp de último disparo (4B)
	t_prev:                 u32,    // Timestamp de disparo previo (4B)
	stdp_pre:               u8,     // Traza STDP pre-sináptica (1B)
	stdp_post:              u8,     // Traza STDP post-sináptica (1B)
	stdp_triplet:           u8,     // Traza Triplet STDP (post lenta) (1B)
	eligibility_fast:       u8,     // Traza de elegibilidad rápida (1B)
	eligibility_slow:       u8,     // Traza de elegibilidad lenta (1B)
	calcium_trace:          u16,    // Traza de calcio intracelular [Ca2+] (2B)
	frequency_homeostasis:  u8,     // Homeostasis de frecuencia (1B)
	axon_delay_exc:         u8,     // Axon delay excitador (1B)
	axon_delay_inh:         u8,     // Axon delay inhibidor (1B)
	axon_delay_desinh:      u8,     // Axon delay desinhibidor (1B)

	// --- 4. Conexiones Sinápticas (84 Bytes — Nibbles / INT4) ---
	axons_exc:              [64]u8, // 128 Axones excitadores (128 pesos @ 4 bits) (64B)
	axons_inh:              [16]u8, // 32 Axones inhibidores (32 pesos @ 4 bits) (16B)
	axons_desinh:           [4]u8,  // 8 Axones desinhibidores (8 pesos @ 4 bits) (4B)

	// --- 5. Árbol Dendrítico (48 Bytes) ---
	// (Nota: Las 32 Dendritas Head son 0 Bytes / Stateless)
	dendrites_sec:          [16]u8, // 16 Dendritas secundarias (16B)
	dendrites_prim:         [8]u8,  // 8 Dendritas primarias (8B)
	gating_dendritic:       [24]u8, // 24 Gating dendrítico (24B)

	// --- 6. Dendritas MoDE — Mixture of Dendritic Experts (12 Bytes) ---
	dendrites_mode:         [4]u8,  // 4 Dendritas MoDE (4B)
	gating_mode:            [4]u8,  // 4 Gating MoDE (4B)
	routers_som:            [4]u8,  // 4 Enrutadores (SOM+) (4B)

	// --- 7. Información Dendritas MoDE (4 Bytes) ---
	stdp_pre_mode:          u8,     // 1 Traza STDP Pre MoDE (1B)
	stdp_post_mode:         u8,     // 1 Traza STDP Post MoDE (1B)
	stdp_post_slow_mode:    u8,     // 1 Traza STDP Post Lenta MoDE (1B)
	homeostasis_mode:       u8,     // 1 Homeostasis de expertos (1B)

	// --- 8. Plasticidad a Corto Plazo — STP Tsodyks-Markram (7 Bytes) ---
	stp_u:                  u16,    // Estado de utilización (u) (2B)
	stp_r:                  u16,    // Estado de recursos (R) (2B)
	stp_tau_fac:            u8,     // Decaimiento de facilitación (tau_fac) (1B)
	stp_tau_rec:            u8,     // Recuperación de depósito (tau_rec) (1B)
	stp_u0:                 u8,     // Sensibilidad basal (U0) (1B)

	// --- 9. Extras, Control & Metaplasticidad (8 Bytes) ---
	bitfield:               u16,    // 16 Flags de estado somático (2B)
	plasticity_fractional:  u16,    // Plasticidad fraccionaria (acumulador estocástico) (2B)
	bcm_threshold:          u16,    // Umbral metaplástico BCM (2B)
	prng_seed:              u16,    // Semilla PRNG local (Xorshift16 determinista) (2B)
}

