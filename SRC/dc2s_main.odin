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

// 
Network :: struct {
	neurons:         []Neuron,
	base_ptr:        uintptr,
	total_neurons:   int,
	active_indices:  [dynamic]int,
	current_tick:    u32,
	target_sparsity: f32,
}

// Memory-address addressing: Retorna el índice relativo sin guardar IDs
// size_of(Neuron) es 192. LLVM lo compila como multiplicación inversa (0 costo de división).
neuron_index_from_ptr :: #force_inline proc(net: ^Network, n_ptr: ^Neuron) -> int {
	return int((uintptr(n_ptr) - net.base_ptr) / size_of(Neuron))
}

init_network :: proc(neuron_count: int, sparsity: f32 = 0.0025) -> ^Network {
	net := new(Network)
	net.total_neurons   = neuron_count
	net.target_sparsity = sparsity
	net.current_tick    = 0
	
	// Buffer dinámico para rastrear las neuronas activas en cada tick (evita recorrer las 250k enteras)
	initial_capacity := int(f32(neuron_count) * sparsity * 2)
	net.active_indices = make([dynamic]int, 0, initial_capacity)

	// Reserva contigua y alineada a 64 bytes para todas las neuronas
	total_bytes := neuron_count * size_of(Neuron)
	raw_mem, err := mem.alloc(total_bytes, 64)
	if err != nil {
		fmt.panicf("Error al reservar memoria para la red: %v", err)
	}

	net.neurons  = mem.slice_ptr(cast(^Neuron)raw_mem, neuron_count)
	net.base_ptr = uintptr(raw_mem)

	// Inicialización biológica basal en enteros (INT16 / INT4)
	for i in 0..<neuron_count {
		n := &net.neurons[i]

		// 1. SOMA & ALIF (Calibrado para que 15 sea el 22% de 68)
		n.v_membrane             = 0    // Potencial de reposo en 0
		n.v_threshold            = 68   // Umbral de disparo base (15 / 68 ≈ 22%)
		n.histeresis             = 0    // Canal frío al arrancar
		n.refractario            = 0    // Sin bloqueo inicial

		// 2. Interneuronas (Apagadas por defecto, esperando Top-Down)
		n.gating_somatic         = 0    // SST+ inactivo
		n.gating_context         = 0    // VIP+ inactivo

		// 3. Info Soma
		n.nmda_latch             = 0
		n.t_last                 = 0
		n.t_prev                 = 0
		n.calcium_trace          = 0
		n.frequency_homeostasis  = 0
		n.axon_delay_exc         = 1    // 1 tick de delay basal
		n.axon_delay_inh         = 1
		n.axon_delay_desinh      = 1

		// 8. STP Tsodyks-Markram (Coma fija de 16 bits)
		n.stp_u                  = 13107 // Utilización basal U0 = ~0.20 (20% de 65535)
		n.stp_r                  = 65535 // Depósito lleno al 100% de recursos
		n.stp_tau_fac            = 15    // Decaimiento rápido de facilitación
		n.stp_tau_rec            = 40    // Recuperación moderada de vesículas
		n.stp_u0                 = 51    // 20% en escala de 8 bits (255 * 0.20)

		// 9. Extras & Metaplasticidad
		n.bitfield               = 0
		n.plasticity_fractional  = 0
		n.bcm_threshold          = 1000  // Umbral BCM inicial
		// La semilla no puede ser 0 para Xorshift16; le damos una distinta a cada una:
		n.prng_seed              = u16((i * 31337 + 1) & 0xFFFF)
	}

	return net
}
