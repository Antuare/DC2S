package main

import "core:fmt"
import "core:mem"
import "core:time"

CACHE_LINE_ALIGNMENT :: 64

// =============================================================================
// ESTRUCTURA DE LA NEURONA (192 Bytes Exactos)
// =============================================================================
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
	dendrites_sec:          [16]u8, // 16 Dendritas secundarias (16B)
	dendrites_prim:         [8]u8,  // 8 Dendritas primarias (8B)
	gating_dendritic:       [24]u8, // 24 Gating dendrítico (24B)

	// --- 6. Dendritas MoDE (12 Bytes) ---
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

// =============================================================================
// CONTENEDOR DE RED
// =============================================================================
Network :: struct {
	neurons:         []Neuron,
	base_ptr:        uintptr,
	total_neurons:   int,
	active_indices:  [dynamic]int,
	current_tick:    u32,
	target_sparsity: f32,
}

// Cálculo de índice relativo mediante aritmética de punteros en memoria
neuron_index_from_ptr :: #force_inline proc(net: ^Network, n_ptr: ^Neuron) -> int {
	return int((uintptr(n_ptr) - net.base_ptr) / size_of(Neuron))
}

// Inicialización de la memoria contigua de la red
init_network :: proc(neuron_count: int, sparsity: f32 = 0.0025) -> ^Network {
	net := new(Network)
	net.total_neurons   = neuron_count
	net.target_sparsity = sparsity
	net.current_tick    = 0

	initial_capacity := int(f32(neuron_count) * sparsity * 2)
	net.active_indices = make([dynamic]int, 0, initial_capacity)

	total_bytes := neuron_count * size_of(Neuron)
	raw_mem, err := mem.alloc(total_bytes, 64)
	if err != nil {
		fmt.panicf("Error al reservar memoria para la red: %v", err)
	}

	net.neurons  = mem.slice_ptr(cast(^Neuron)raw_mem, neuron_count)
	net.base_ptr = uintptr(raw_mem)

	// Inicialización basal
	for i in 0..<neuron_count {
		n := &net.neurons[i]

		n.v_membrane             = 0
		n.v_threshold            = 68   // 15 es ~22% de 68
		n.histeresis             = 0
		n.refractario            = 0

		n.gating_somatic         = 0
		n.gating_context         = 0
		n.nmda_latch             = 0
		n.t_last                 = 0
		n.t_prev                 = 0
		n.calcium_trace          = 0
		n.frequency_homeostasis  = 0
		n.axon_delay_exc         = 1
		n.axon_delay_inh         = 1
		n.axon_delay_desinh      = 1

		// Habilitar las compuertas dendríticas primarias para paso de señal
		for d in 0..<8 {
			n.gating_dendritic[d] = 1
		}

		// Pesos iniciales INT4: cargamos las primeras 8 conexiones espaciales con fuerza máxima (15)
		// Dos pesos por byte: 0xFF = dos conexiones con peso 15
		n.axons_exc[0] = 0xFF 
		n.axons_exc[1] = 0xFF 
		n.axons_exc[2] = 0xFF 
		n.axons_exc[3] = 0xFF 

		// STP Tsodyks-Markram
		n.stp_u                  = 13107 // U0 = 20%
		n.stp_r                  = 65535 // Depósito al 100%
		n.stp_tau_fac            = 15
		n.stp_tau_rec            = 40
		n.stp_u0                 = 51

		n.bitfield               = 0
		n.plasticity_fractional  = 0
		n.bcm_threshold          = 1000
		n.prng_seed              = u16((i * 31337 + 1) & 0xFFFF)
	}

	return net
}

destroy_network :: proc(net: ^Network) {
	if net == nil do return
	delete(net.active_indices)
	mem.free(rawptr(net.base_ptr))
	free(net)
}

// -----------------------------------------------------------------------------
// INYECCIÓN DE ESTÍMULO (El Rayo que entra por Z = 0)
// -----------------------------------------------------------------------------
inject_input_pulse :: proc(net: ^Network, center_x, center_y: int, radius: int) {
	injected_count := 0

	for dx := -radius; dx <= radius; dx++ {
		for dy := -radius; dy <= radius; dy++ {
			x := center_x + dx
			y := center_y + dy

			if x >= 0 && x < GRID_DIM_X && y >= 0 && y < GRID_DIM_Y {
				// Inyectamos en la cara de entrada Z = 0
				idx := coord_to_index(x, y, 0)
				n := &net.neurons[idx]

				// Rompemos el umbral intencionalmente para forzar el disparo inicial
				n.v_membrane = n.v_threshold + 10
				append(&net.active_indices, idx)
				injected_count += 1
			}
		}
	}

	fmt.printf("Descarga inyectada en Z=0: %d neuronas activadas como frente de onda.\n", injected_count)
}

// =============================================================================
// MAIN: PUNTO DE ENTRADA Y BENCHMARK REAL
// =============================================================================
main :: proc() {
	fmt.println("==================================================")
	fmt.println("       INICIALIZANDO MOTOR DC2S — NoTA           ")
	fmt.println("==================================================")

	NUM_NEURONS :: 250_000
	fmt.printf("[*] Struct Neuron: %d Bytes (Exacto)\n", size_of(Neuron))
	fmt.printf("[*] Instanciando red de %d neuronas en memoria...\n", NUM_NEURONS)

	start_mem := time.now()
	net := init_network(NUM_NEURONS)
	defer destroy_network(net)

	mem_mb := f32(net.total_neurons * size_of(Neuron)) / (1024.0 * 1024.0)
	fmt.printf("[+] Red instanciada en %.2f ms\n", time.duration_milliseconds(time.since(start_mem)))
	fmt.printf("[+] Memoria física: %.2f MB contiguos en RAM\n", mem_mb)

	// 1. Construir la topología 3D de Iris (50 x 50 x 100)
	build_iris_3d_grid(net)

	// 2. Disparar el Rayo en el centro de la cara de entrada (X=25, Y=25, Z=0)
	fmt.println("\n--- DISPARANDO TRUENO EXPERIMENTAL ---")
	inject_input_pulse(net, 25, 25, radius = 2)

	// 3. Ejecutar 40 ticks a través de loop.odin y medir la propagación
	TOTAL_TICKS :: 40
	fmt.Printf("\n[*] Simulando %d Ticks a través de loop.odin (Bi-Wave)...\n", TOTAL_TICKS)
	fmt.println("----------------------------------------------------------------------")
	fmt.println(" Tick | Activas | Esparsidad | Profundidad Máx (Z) | Estado de Onda  ")
	fmt.println("----------------------------------------------------------------------")

	start_sim := time.now()
	max_z_reached := 0

	for t in 1..=TOTAL_TICKS {
		step_network(net)

		active_count := len(net.active_indices)
		sparsity_pct := (f32(active_count) / f32(net.total_neurons)) * 100.0

		// Encontrar la profundidad máxima en Z alcanzada por la onda en este tick
		current_max_z := 0
		for idx in net.active_indices {
			_, _, z := index_to_coord(idx)
			if z > current_max_z do current_max_z = z
		}
		if current_max_z > max_z_reached do max_z_reached = current_max_z

		// Diagnóstico del estado del rayo
		status := "Propagando..."
		if current_max_z == GRID_DIM_Z - 1 {
			status = "¡IMPACTO EN TIERRA (Z=99)!"
		} else if active_count == 0 {
			status = "Onda Disipada (Fin)"
		}

		fmt.printf(" %4d | %7d | %9.3f%% |       Z = %3d       | %s\n", 
			t, active_count, sparsity_pct, max_z_reached, status)

		// Si la energía se disipó por completo, terminamos la simulación
		if active_count == 0 do break
	}

	sim_duration := time.since(start_sim)
	fmt.println("----------------------------------------------------------------------")
	fmt.printf("[✓] Simulación completada en: %.2f ms de tiempo real de CPU\n", time.duration_milliseconds(sim_duration))
	fmt.printf("[+] Profundidad máxima alcanzada: Capa Z = %d / %d\n", max_z_reached, GRID_DIM_Z - 1)
	
	if max_z_reached >= GRID_DIM_Z - 1 {
		fmt.println("La onda cruzó el bloque 3D de extremo a extremo!")
	} else {
		fmt.println("[!] La onda se mitigó en el interior.")
	}

	fmt.println("==================================================")
}
