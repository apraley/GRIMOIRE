# Content Reference

This is a reference dump of GRIMOIRE's static data tables — the numbers that
worldgen, the daily simulation and the action registry all draw from. Every
table below is generated directly from `grimoire/content_econ.py`,
`grimoire/content_social.py`, `grimoire/content_conflict.py` and
`grimoire/content_tech.py` by [`gen_tables.py`](gen_tables.py) in this
directory, so it cannot drift out of sync with the source the way a
hand-copied table would. Regenerate it with:

```
python3 docs/gen_tables.py > docs/CONTENT.md
```

(then re-add this header, which the script does not emit). For what these
numbers *do* — how a tech's `e` dict is consumed, how an operation's `risk`
becomes an exposure roll — see [`SYSTEMS.md`](SYSTEMS.md). For how to use
them in play, see [`PLAYING.md`](PLAYING.md).

---

## Commodities

All 48 tradeable goods, grouped by category. `tier` is raw (0) through advanced/strategic (3). `elast` is price elasticity of demand — higher means price swings faster with a supply/demand gap. `perish` is the fraction of a stockpile lost per day (power at 1.000 cannot be warehoused at all: it is generated and consumed the same day). `strat` is strategic weight, which drives sanctions targeting and war goals. `bulk` scales shipping cost.

### chem

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| chemicals | refined | $1.25K | 0.40 | 0.001 | 0.65 | 1.2 |
| fertilizer | refined | $560 | 0.30 | 0.001 | 0.65 | 1.3 |

### consumer

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| luxury | manufactured | $19K | 1.40 | 0.000 | 0.05 | 0.8 |
| textiles | refined | $760 | 0.70 | 0.001 | 0.20 | 1.1 |
| vehicles | manufactured | $9.8K | 0.75 | 0.001 | 0.45 | 1.4 |

### culture

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| media | manufactured | $2.4K | 1.20 | 0.030 | 0.45 | 0.0 |

### energy

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| coal | raw | $180 | 0.30 | 0.000 | 0.55 | 1.6 |
| crude | raw | $620 | 0.25 | 0.000 | 1.00 | 1.1 |
| fuel | refined | $980 | 0.30 | 0.001 | 0.95 | 1.1 |
| gas | raw | $430 | 0.30 | 0.002 | 0.90 | 1.5 |
| power | refined | $520 | 0.25 | 1.000 | 0.90 | 0.0 |
| uranium | raw | $9.5K | 0.15 | 0.000 | 1.00 | 0.7 |

### food

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| coffee | refined | $1.4K | 0.85 | 0.003 | 0.10 | 1.0 |
| fish | raw | $700 | 0.55 | 0.040 | 0.30 | 1.7 |
| foodstuffs | refined | $780 | 0.40 | 0.008 | 0.70 | 1.2 |
| grain | raw | $200 | 0.35 | 0.004 | 0.75 | 1.3 |
| livestock | raw | $900 | 0.60 | 0.006 | 0.30 | 1.8 |
| produce | raw | $380 | 0.55 | 0.030 | 0.35 | 1.6 |
| spirits | manufactured | $2.1K | 0.95 | 0.000 | 0.05 | 1.1 |

### health

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| medtech | advanced | $24K | 0.30 | 0.001 | 0.60 | 0.6 |
| pharma | manufactured | $12.5K | 0.25 | 0.004 | 0.80 | 0.6 |

### illicit

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| contraband | manufactured | $34K | 0.90 | 0.010 | 0.30 | 0.5 |

### industry

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| aircraft | advanced | $88K | 0.55 | 0.000 | 0.85 | 1.2 |
| machinery | manufactured | $5.4K | 0.45 | 0.000 | 0.70 | 1.3 |
| ships | advanced | $76K | 0.50 | 0.000 | 0.80 | 2.2 |

### material

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| alloys | refined | $2.3K | 0.35 | 0.000 | 0.90 | 1.1 |
| cement | refined | $140 | 0.30 | 0.002 | 0.35 | 2.0 |
| glass | refined | $420 | 0.45 | 0.000 | 0.20 | 1.5 |
| plastics | refined | $880 | 0.45 | 0.000 | 0.45 | 1.2 |
| steel | refined | $690 | 0.35 | 0.000 | 0.85 | 1.5 |

### military

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| arms | advanced | $27K | 0.35 | 0.000 | 1.00 | 1.2 |
| munitions | manufactured | $3.1K | 0.30 | 0.001 | 0.95 | 1.4 |

### mineral

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| bauxite | raw | $310 | 0.30 | 0.000 | 0.50 | 1.6 |
| copper | raw | $1.45K | 0.35 | 0.000 | 0.75 | 1.2 |
| gems | raw | $42K | 1.10 | 0.000 | 0.20 | 0.3 |
| gold | raw | $61K | 0.60 | 0.000 | 0.45 | 0.4 |
| iron | raw | $210 | 0.30 | 0.000 | 0.70 | 1.7 |
| lithium | raw | $4.2K | 0.40 | 0.000 | 0.90 | 1.0 |
| rare_earth | raw | $8.8K | 0.25 | 0.000 | 1.00 | 0.8 |
| timber | raw | $170 | 0.40 | 0.001 | 0.25 | 1.9 |

### service

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| finance | manufactured | $4.1K | 0.85 | 0.020 | 0.60 | 0.0 |
| logistics | manufactured | $1.6K | 0.40 | 0.050 | 0.70 | 0.0 |

### space

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| satellites | advanced | $210K | 0.35 | 0.000 | 0.95 | 0.9 |

### tech

| good | tier | base price | elasticity | perish/day | strategic | bulk |
|---|---|---|---|---|---|---|
| compute | advanced | $15K | 0.35 | 0.010 | 1.00 | 0.2 |
| electronics | manufactured | $7.6K | 0.65 | 0.002 | 0.80 | 0.7 |
| robotics | advanced | $42K | 0.45 | 0.001 | 0.90 | 0.8 |
| semis | advanced | $31K | 0.30 | 0.001 | 1.00 | 0.4 |
| software | advanced | $6.8K | 0.55 | 0.006 | 0.70 | 0.0 |

## Industries

All 52 production recipes. `out` is the good produced (one unit of capacity is one worker-equivalent job). `inputs` lists physical inputs consumed per unit of output. `capital` and `skill` (0..1) describe how capital- and education-intensive the process is; `dirty` (0..1) drives pollution; `land` is land use per unit; `gates on` names the regional resource endowment (from `RESOURCE_GATES`) that must be present for a region to host the industry at all, where one applies. `tech` names a prerequisite technology.

| industry | out | inputs (per unit) | capital | skill | dirty | land | gates on | tech |
|---|---|---|---|---|---|---|---|---|
| aeroworks | aircraft | alloys 0.4, electronics 0.18, machinery 0.12, power 0.14 | 4.40 | 0.78 | 0.30 | 0.2 | — | composite_airframe |
| alloyworks | alloys | steel 0.5, copper 0.15, rare_earth 0.02, power 0.25 | 2.60 | 0.55 | 0.65 | 0.1 | — | alloy_metallurgy |
| armsworks | arms | alloys 0.25, electronics 0.15, machinery 0.1, chemicals 0.08 | 3.00 | 0.68 | 0.45 | 0.2 | — | — |
| atelier | luxury | gems 0.05, gold 0.02, textiles 0.2 | 0.80 | 0.55 | 0.05 | 0.0 | — | — |
| autoworks | vehicles | steel 0.4, plastics 0.12, electronics 0.1, machinery 0.05, power 0.14 | 2.40 | 0.50 | 0.40 | 0.1 | — | — |
| banks | finance | software 0.05, compute 0.03 | 1.20 | 0.75 | 0.01 | 0.0 | — | — |
| cementworks | cement | power 0.2, coal 0.15 | 1.20 | 0.22 | 0.95 | 0.1 | — | — |
| chemworks | chemicals | crude 0.25, gas 0.2, power 0.18 | 2.20 | 0.50 | 0.85 | 0.1 | — | — |
| coal_mine | coal | machinery 0.003 | 0.90 | 0.18 | 0.95 | 0.3 | coal | — |
| datacenters | compute | semis 0.1, power 0.7 | 4.00 | 0.75 | 0.20 | 0.1 | — | hyperscale |
| distillery | spirits | grain 0.55, glass 0.08, power 0.05 | 0.90 | 0.30 | 0.25 | 0.1 | — | — |
| electroworks | electronics | semis 0.06, copper 0.08, plastics 0.1, power 0.12 | 2.20 | 0.62 | 0.35 | 0.1 | — | — |
| fabs | semis | chemicals 0.2, rare_earth 0.03, power 0.55, machinery 0.03 | 6.50 | 0.88 | 0.30 | 0.1 | — | euv_litho |
| farming | grain | fertilizer 0.05, fuel 0.03 | 0.50 | 0.15 | 0.20 | 1.0 | arable | — |
| fertplant | fertilizer | gas 0.35, chemicals 0.1, power 0.12 | 1.60 | 0.40 | 0.70 | 0.1 | — | — |
| fishing | fish | fuel 0.1 | 0.90 | 0.22 | 0.20 | 0.0 | fishery | — |
| food_proc | foodstuffs | grain 0.5, produce 0.2, livestock 0.15, power 0.08 | 1.10 | 0.30 | 0.20 | 0.1 | — | — |
| forestry | timber | fuel 0.05 | 0.60 | 0.15 | 0.40 | 1.6 | timber | — |
| gas_extract | gas | machinery 0.005, power 0.04 | 2.00 | 0.35 | 0.60 | 0.2 | gas | — |
| gemworks | gems | power 0.05 | 1.00 | 0.35 | 0.35 | 0.2 | gems | — |
| glassworks | glass | power 0.22 | 1.10 | 0.28 | 0.45 | 0.1 | — | — |
| machineshops | machinery | steel 0.45, alloys 0.1, electronics 0.04, power 0.15 | 2.00 | 0.55 | 0.35 | 0.1 | — | — |
| medtechworks | medtech | electronics 0.2, alloys 0.1, plastics 0.08 | 3.20 | 0.85 | 0.15 | 0.1 | — | bioimaging |
| millworks | textiles | chemicals 0.1, power 0.08 | 0.80 | 0.20 | 0.40 | 0.1 | — | — |
| mining_au | gold | chemicals 0.08, power 0.1 | 1.80 | 0.30 | 0.70 | 0.2 | gold | — |
| mining_bx | bauxite | fuel 0.09 | 1.30 | 0.24 | 0.60 | 0.3 | bauxite | — |
| mining_cu | copper | fuel 0.1, power 0.06 | 1.60 | 0.28 | 0.65 | 0.3 | copper | — |
| mining_iron | iron | fuel 0.08, machinery 0.004 | 1.40 | 0.25 | 0.60 | 0.3 | iron | — |
| mining_li | lithium | power 0.15, chemicals 0.05 | 2.00 | 0.40 | 0.55 | 0.3 | lithium | brine_extraction |
| mining_re | rare_earth | chemicals 0.12, power 0.18 | 2.40 | 0.45 | 0.85 | 0.3 | rare_earth | rare_separation |
| oil_extract | crude | machinery 0.006, power 0.05 | 2.20 | 0.35 | 0.75 | 0.2 | oil | — |
| orchards | produce | fertilizer 0.06, fuel 0.03 | 0.50 | 0.18 | 0.15 | 0.8 | arable | — |
| ordnance | munitions | chemicals 0.35, steel 0.2, power 0.1 | 1.80 | 0.40 | 0.70 | 0.2 | — | — |
| pharmaworks | pharma | chemicals 0.3, power 0.1 | 3.00 | 0.80 | 0.35 | 0.1 | — | — |
| plantations | coffee | fertilizer 0.08 | 0.40 | 0.12 | 0.25 | 1.4 | tropical | — |
| plasticworks | plastics | chemicals 0.55, power 0.1 | 1.40 | 0.35 | 0.60 | 0.1 | — | — |
| power_fossil | power | coal 0.35, gas 0.2 | 2.00 | 0.40 | 1.00 | 0.1 | — | — |
| power_fusion | power | alloys 0.004, compute 0.0006 | 7.00 | 0.90 | 0.01 | 0.2 | — | fusion_ignition |
| power_nuclear | power | uranium 0.004, water 0 | 4.20 | 0.70 | 0.10 | 0.1 | — | fission_gen3 |
| power_solar | power | semis 0.0008 | 2.60 | 0.45 | 0.03 | 0.6 | — | pv_thinfilm |
| power_wind | power | alloys 0.002 | 2.40 | 0.45 | 0.03 | 0.5 | — | turbine_offshore |
| ranching | livestock | grain 0.45, fuel 0.04 | 0.60 | 0.18 | 0.45 | 2.2 | pasture | — |
| refining | fuel | crude 0.9, power 0.1 | 2.40 | 0.45 | 0.80 | 0.1 | — | — |
| roboworks | robotics | electronics 0.25, alloys 0.15, software 0.08, machinery 0.06 | 3.80 | 0.82 | 0.20 | 0.1 | — | actuator_dense |
| shipping | logistics | fuel 0.3, ships 0.002, vehicles 0.004 | 2.00 | 0.30 | 0.75 | 0.1 | — | — |
| shipyards | ships | steel 0.6, machinery 0.14, electronics 0.08, power 0.12 | 3.40 | 0.55 | 0.50 | 0.4 | — | — |
| smuggling (illegal) | contraband | chemicals 0.1, logistics 0.06 | 0.60 | 0.35 | 0.30 | 0.1 | — | — |
| softworks | software | compute 0.08 | 0.50 | 0.85 | 0.02 | 0.0 | — | — |
| spaceworks | satellites | alloys 0.3, electronics 0.25, semis 0.05, fuel 0.2 | 5.50 | 0.90 | 0.30 | 0.2 | — | orbital_lift |
| steelworks | steel | iron 0.85, coal 0.3, power 0.2 | 2.00 | 0.38 | 0.90 | 0.1 | — | — |
| studios | media | compute 0.04, power 0.02 | 0.70 | 0.60 | 0.02 | 0.0 | — | — |
| uranium_mine | uranium | chemicals 0.15, power 0.2 | 2.60 | 0.55 | 0.90 | 0.2 | uranium | isotope_sep |

## Technology tree

All 83 technologies, grouped by field, in ascending cost order within a field. `cost` is research-points required (see docs/SYSTEMS.md for how nations and the player accumulate research points). `prereqs` lists technologies that must already be held.

### agriculture

| technology | cost | prereqs | effect |
|---|---|---|---|
| precision_ag | 900 | — | Sensor-guided inputs; fewer tonnes of fertiliser for more tonnes of grain. |
| drought_cultivars | 1600 | precision_ag | Cultivars that shrug at a failed monsoon. |
| aquaculture_3 | 2100 | precision_ag | Closed-loop marine farming that does not strip the shelf. |
| vertical_farms | 3200 | precision_ag, led_efficiency | Calories grown in towers, priced in kilowatts. |
| cultured_protein | 4800 | gene_editing | Meat without the animal, at last cheaper than the animal. |
| nitrogen_fix | 5600 | catalysis, gene_editing | Cereals that fix their own nitrogen. Fertiliser markets never recover. |

### materials

| technology | cost | prereqs | effect |
|---|---|---|---|
| led_efficiency | 700 | — | Lighting and displays at a fraction of the draw. |
| alloy_metallurgy | 800 | — | High-performance alloys for turbines, hulls, and barrels. |
| brine_extraction | 1100 | — | Direct lithium extraction from brine at industrial scale. |
| catalysis | 1200 | — | Catalysts that make hard reactions cheap. |
| rare_separation | 1900 | catalysis | Solvent chemistry that pulls lanthanides apart economically. |
| composite_airframe | 2400 | alloy_metallurgy | Airframes that are lighter than the arguments about them. |
| desalination_4 | 2600 | catalysis | Membranes that make the sea drinkable at coal prices. |
| carbon_capture | 4200 | catalysis | Direct air capture that finally beats its own energy bill. |
| nanofab | 5200 | euv_litho | Atom-scale assembly, still slow, no longer theoretical. |
| metamaterials | 6400 | nanofab | Structures that bend fields the way lenses bend light. |
| superconductors | 8800 | metamaterials, cryogenics | Room-temperature superconduction. The grid stops leaking. |

### energy

| technology | cost | prereqs | effect |
|---|---|---|---|
| pv_thinfilm | 1000 | — | Photovoltaics printed by the square kilometre. |
| turbine_offshore | 1300 | alloy_metallurgy | Floating turbines in water too deep to anchor. |
| grid_storage | 2200 | pv_thinfilm | Storage that turns intermittent power into baseload. |
| cryogenics | 2300 | — | Industrial cold, cheaply. |
| fission_gen3 | 2600 | alloy_metallurgy | Passively safe reactors that regulators can be argued into. |
| isotope_sep | 2900 | fission_gen3 | Centrifuge cascades. Also the first step to something else. |
| breeder_cycle | 5400 | fission_gen3, isotope_sep | Reactors that make more fuel than they burn. |
| plasma_control | 7200 | ml_scaling, superconductors | Real-time magnetohydrodynamic control of a burning plasma. |
| beamed_power | 9600 | orbital_lift, metamaterials | Power from orbit, delivered as microwave rain. |
| fusion_ignition | 14000 | superconductors, plasma_control | Net-positive fusion. Everything downstream of energy price changes. |

### computing

| technology | cost | prereqs | effect |
|---|---|---|---|
| hyperscale | 2000 | — | Datacentres measured in gigawatts, not racks. |
| euv_litho | 3400 | — | Extreme-ultraviolet lithography. Four companies on Earth can do it. |
| swarm_net | 3800 | hyperscale | Mesh networking that survives the loss of any node. |
| post_quantum | 4600 | euv_litho | Lattice cryptography that survives the machines that break the rest. |
| neuromorphic | 6600 | nanofab | Chips that compute the way tissue does — badly, but for nothing. |
| photonic_compute | 7800 | euv_litho, metamaterials | Optical interconnect ends the memory wall. |
| quantum_error | 9800 | cryogenics, photonic_compute | Fault-tolerant qubits. Every archived secret becomes readable. |

### ai

| technology | cost | prereqs | effect |
|---|---|---|---|
| ml_scaling | 2800 | hyperscale | Scaling laws hold longer than anyone budgeted for. |
| synthetic_media | 3200 | ml_scaling | Perfect fabricated footage. Evidence stops meaning anything. |
| predictive_police | 4400 | agentic_systems | Arrests made before the crime, with the error bars kept classified. |
| agentic_systems | 5200 | ml_scaling | Software that pursues goals across weeks without supervision. |
| alignment_theory | 6800 | world_models | A real theory of control for systems smarter than their operators. |
| world_models | 8400 | agentic_systems, photonic_compute | Models that simulate economies and armies well enough to bet on. |
| autonomous_labs | 9200 | world_models, robotics_dense | Closed-loop laboratories that run experiments while you sleep. |
| recursive_design | 16000 | autonomous_labs, quantum_error | Systems that improve their own successors. The curve leaves the page. |

### biotech

| technology | cost | prereqs | effect |
|---|---|---|---|
| mrna_platform | 2000 | — | Vaccine design in weeks rather than years. |
| gene_editing | 2400 | — | Cheap, precise edits to any genome you can sequence. |
| proteomics | 3000 | ml_scaling | Structure prediction closes the loop from sequence to drug. |
| bioremediation | 3600 | synthetic_bio | Engineered organisms that eat the last century's mistakes. |
| synthetic_bio | 5800 | gene_editing | Organisms designed as factories. Dual-use to the core. |
| longevity_1 | 7400 | gene_editing, proteomics | Senolytics that add healthy years for those who can pay. |
| neural_interface | 8600 | neuromorphic, proteomics | High-bandwidth interfaces. The applications are not all medical. |

### space

| technology | cost | prereqs | effect |
|---|---|---|---|
| orbital_lift | 3600 | composite_airframe | Fully reusable heavy lift. Orbit becomes a freight problem. |
| deep_sensors | 4200 | orbital_lift, swarm_net | Persistent global overhead coverage at sub-metre resolution. |
| orbital_manufact | 6800 | orbital_lift, robotics_dense | Vacuum and microgravity as industrial inputs. |
| lunar_isru | 9400 | orbital_manufact | Propellant and metal from regolith. The Moon stops being a cost centre. |
| asteroid_mining | 13000 | lunar_isru, autonomous_labs | The first captured body pays for the entire programme twice. |

### weapons

| technology | cost | prereqs | effect |
|---|---|---|---|
| guided_muni | 1400 | — | Precision guidance as the default, not the exception. |
| drone_swarm | 3400 | swarm_net, agentic_systems | Attritable mass. Numbers become a technology again. |
| cyber_arsenal | 4800 | agentic_systems | Pre-positioned access in every grid that matters. |
| hypersonics | 6200 | composite_airframe, guided_muni | Manoeuvring reentry that current defences cannot solve. |
| directed_energy | 7600 | superconductors, grid_storage | Cost-per-shot measured in cents. Drone swarms get expensive again. |
| fission_device | 8200 | isotope_sep, guided_muni | A deliverable fission weapon. The strategic table is rewritten. |
| autonomous_arms | 8800 | drone_swarm, world_models | Weapons that select their own targets. Treaties lag by a decade. |
| missile_defence | 11000 | directed_energy, deep_sensors | Layered interception. Deterrence starts to wobble. |
| thermonuclear | 12500 | fission_device | Staged devices. Yields no longer bounded by fissile mass. |
| orbital_strike | 15500 | orbital_manufact, hypersonics | Kinetic bombardment from orbit. No warning worth the name. |

### medicine

| technology | cost | prereqs | effect |
|---|---|---|---|
| bioimaging | 1800 | — | Imaging that catches disease a decade early. |
| public_health_ai | 3200 | ml_scaling, bioimaging | Outbreak detection from sewage, pharmacy tills, and search logs. |
| universal_vax | 6400 | mrna_platform, proteomics | Broad-spectrum prophylaxis against whole viral families. |
| regen_medicine | 7800 | gene_editing, bioimaging | Grown organs on demand. Transplant waiting lists end. |

### social

| technology | cost | prereqs | effect |
|---|---|---|---|
| digital_id | 1600 | hyperscale | One identity per citizen, cryptographically enforced. |
| behavioural_nudge | 2600 | ml_scaling | Choice architecture applied at national scale. |
| mass_deliberation | 3400 | digital_id | Sortition assemblies with real statutory power. |
| algorithmic_gov | 4600 | agentic_systems, digital_id | Policy set by optimiser. Efficient, and nobody can appeal it. |
| social_credit | 5200 | digital_id, predictive_police | Compliance priced into every transaction a citizen makes. |

### logistics

| technology | cost | prereqs | effect |
|---|---|---|---|
| cold_chain_global | 1900 | cryogenics | Unbroken refrigeration from field to shelf, anywhere. |
| actuator_dense | 2200 | alloy_metallurgy | Power-dense actuators; machines that move like animals. |
| modular_ports | 2800 | autonomous_freight | Ports that reconfigure themselves for whatever arrives. |
| autonomous_freight | 3000 | agentic_systems | Crewless hulls and driverless corridors. |
| robotics_dense | 4000 | actuator_dense, ml_scaling | Robots that work in spaces designed for people. |

### finance

| technology | cost | prereqs | effect |
|---|---|---|---|
| cbdc | 2400 | digital_id | Programmable sovereign money. Every transaction is policy. |
| algo_markets | 3000 | ml_scaling | Machine market-making: tighter spreads, fatter tails. |
| settlement_mesh | 4400 | post_quantum, cbdc | Cross-border settlement without a correspondent bank in sight. |
| shadow_ledger | 5600 | post_quantum | Provably private value transfer at institutional scale. |
| risk_synthesis | 6200 | world_models, algo_markets | Systemic risk modelled well enough to trade against. |

### Player megaprojects

Not nation-level tech; these are the six endgame programmes a player can run personally with `project` / `invest_project` once the prerequisite techs are held privately (see `study`).

| project | cost | requires | effect |
|---|---|---|---|
| singularity_engine | 52000 | recursive_design, fusion_ignition | A self-improving industrial intelligence with a physical economy beneath it. |
| orbital_ring | 64000 | orbital_manufact, superconductors, asteroid_mining | A structure that makes orbit a commute and makes you its landlord. |
| panopticon | 38000 | social_credit, deep_sensors, quantum_error | Total-information awareness over every network on the planet. |
| eternal_program | 44000 | longevity_1, regen_medicine, neural_interface | Indefinite lifespan for a controlled list of names, starting with yours. |
| world_reserve | 30000 | settlement_mesh, cbdc, risk_synthesis | A settlement layer every central bank is forced to clear through. |
| doctrine_engine | 34000 | synthetic_media, behavioural_nudge, world_models | Narrative production tuned per-person, per-day, at planetary scale. |

## Military unit types

All 24 unit types. `cost` is the one-time procurement price; `up` is daily upkeep; `men` is manpower per unit; `supply` is tonnes of logistics consumption per day; `build` is days from order to fielding. `atk`/`dfn` are combat factors folded into `Nation.military_score()` and battle resolution.

| unit | domain | atk | dfn | hp | cost | upkeep/day | men | supply/day | tech | build days |
|---|---|---|---|---|---|---|---|---|---|---|
| militia | land | 0.30 | 0.45 | 1.0 | $26M | $90K | 4,000 | 0.6 | — | 20 |
| infantry | land | 0.70 | 0.85 | 1.0 | $95M | $420K | 5,000 | 1.0 | — | 45 |
| mech_inf | land | 1.00 | 1.05 | 1.3 | $260M | $1.1M | 5,200 | 2.2 | alloy_metallurgy | 70 |
| armour | land | 1.70 | 1.15 | 1.6 | $440M | $1.9M | 3,800 | 3.4 | alloy_metallurgy | 90 |
| artillery | land | 1.45 | 0.55 | 0.9 | $210M | $1.2M | 2,600 | 2.8 | — | 60 |
| rocket_arty | land | 1.95 | 0.40 | 0.8 | $360M | $1.8M | 2,100 | 3.6 | guided_muni | 75 |
| special_ops | land | 1.25 | 0.75 | 0.7 | $310M | $1.6M | 900 | 0.9 | — | 110 |
| air_defence | land | 0.25 | 1.90 | 1.0 | $340M | $1.5M | 1,800 | 1.6 | guided_muni | 80 |
| engineers | land | 0.25 | 0.70 | 1.0 | $140M | $600K | 3,000 | 1.4 | — | 50 |
| fighter_wing | air | 1.60 | 1.40 | 0.9 | $720M | $3.4M | 1,400 | 3.0 | composite_airframe | 110 |
| strike_wing | air | 2.20 | 0.70 | 0.8 | $860M | $4M | 1,500 | 3.8 | guided_muni | 120 |
| bomber_wing | air | 2.90 | 0.50 | 1.0 | $1.9B | $7.5M | 2,200 | 6.0 | composite_airframe | 180 |
| transport_air | air | 0.05 | 0.30 | 0.9 | $410M | $2.1M | 1,100 | 2.4 | — | 90 |
| drone_wing | air | 1.35 | 0.55 | 0.5 | $160M | $700K | 350 | 1.0 | drone_swarm | 45 |
| frigate_sqn | sea | 0.95 | 1.20 | 1.1 | $580M | $2.6M | 1,600 | 2.4 | — | 140 |
| destroyer_sqn | sea | 1.55 | 1.55 | 1.4 | $1.4B | $5.4M | 2,400 | 3.6 | alloy_metallurgy | 190 |
| sub_flotilla | sea | 2.10 | 0.95 | 1.0 | $2.2B | $6.8M | 900 | 2.0 | alloy_metallurgy | 230 |
| carrier_grp | sea | 3.20 | 2.20 | 2.2 | $11B | $26M | 9,000 | 12.0 | composite_airframe | 420 |
| amphib_grp | sea | 1.10 | 1.00 | 1.3 | $1.9B | $6.2M | 5,200 | 4.5 | — | 210 |
| cyber_cmd | cyber | 1.40 | 1.60 | 0.6 | $320M | $2.4M | 1,200 | 0.2 | cyber_arsenal | 70 |
| space_cmd | space | 0.90 | 1.30 | 0.8 | $2.4B | $9M | 800 | 0.6 | deep_sensors | 200 |
| abm_shield | space | 0.10 | 3.00 | 1.2 | $6.5B | $21M | 1,600 | 1.2 | missile_defence | 380 |
| icbm_field | nuclear | 9.00 | 0.10 | 1.0 | $3.8B | $14M | 1,200 | 0.8 | fission_device | 300 |
| boomer_sqn | nuclear | 8.00 | 1.20 | 1.4 | $7.4B | $24M | 1,400 | 1.4 | thermonuclear | 460 |

## Intelligence operations

All 20 operations available through `launch_op` (the player reaches most of these directly; see docs/PLAYING.md for the command names). `risk` is the base chance of exposure on any attempt; `heat` is how much heat/notoriety an exposed attempt generates; `days` is base time to resolution; `cost` is the base budget, which can be overspent for faster/likelier success.

| operation | skill | risk | heat | days | cost | description |
|---|---|---|---|---|---|---|
| surveil | surveillance | 0.06 | 0.02 | 5 | $200K | Build a pattern of life on a target. |
| recruit_asset | tradecraft | 0.14 | 0.06 | 12 | $1.2M | Turn an insider into your source. |
| steal_tech | hacking | 0.22 | 0.14 | 18 | $3.5M | Exfiltrate a research programme. |
| steal_funds | hacking | 0.26 | 0.20 | 14 | $1.8M | Move money out of an institution quietly. |
| sabotage | infiltration | 0.30 | 0.26 | 16 | $4M | Take an industrial or military asset offline. |
| blackmail | tradecraft | 0.18 | 0.16 | 9 | $800K | Convert a secret into obedience. |
| bribe | negotiation | 0.12 | 0.10 | 4 | $0 | Buy a decision outright. |
| disinfo | propaganda | 0.16 | 0.12 | 10 | $2.6M | Push a fabricated narrative into the information space. |
| assassinate | assassination | 0.42 | 0.55 | 22 | $9M | Remove a person permanently. |
| kidnap | infiltration | 0.40 | 0.48 | 18 | $6M | Take someone off the board and keep them. |
| coup_prep | politics | 0.34 | 0.42 | 45 | $42M | Assemble the officers, the broadcaster, and the list. |
| false_flag | tradecraft | 0.45 | 0.62 | 30 | $28M | Stage an attack attributed to someone else. |
| counterintel | surveillance | 0.05 | 0.02 | 14 | $2.2M | Hunt for foreign penetration of your own organisation. |
| cyber_intrude | hacking | 0.20 | 0.15 | 11 | $2.4M | Pre-position access inside critical infrastructure. |
| arm_insurgents | smuggling | 0.32 | 0.45 | 35 | $36M | Supply a rebel movement with weapons and money. |
| extract | infiltration | 0.28 | 0.22 | 8 | $3M | Pull one of your people out before they are taken. |
| plant_evidence | forgery | 0.24 | 0.30 | 12 | $1.6M | Manufacture a paper trail that convicts. |
| seduce_target | seduction | 0.20 | 0.14 | 16 | $600K | A relationship built entirely as an access route. |
| leak | propaganda | 0.15 | 0.20 | 6 | $300K | Give a real secret to a journalist at the right moment. |
| frame_rival | deception | 0.30 | 0.34 | 20 | $5.5M | Make an enemy's downfall look like their own doing. |

## Government types

All 14 government forms nations can generate with. `repress` and `legit_base` seed `Nation.repression`/`.legitimacy`; `corrupt` seeds baseline corruption; `coup_risk` scales into the daily coup-attempt probability; `speed` is how fast policy can drift toward the ruling ideology.

| government | elections | repress | legit base | corrupt | coup risk | speed | description |
|---|---|---|---|---|---|---|---|
| liberal_democracy | yes | 0.10 | 0.62 | 0.22 | 0.02 | 0.55 | Competitive elections, courts with teeth, a press that bites. |
| flawed_democracy | yes | 0.24 | 0.52 | 0.40 | 0.06 | 0.65 | Elections happen. So does vote-buying. |
| dominant_party | yes | 0.48 | 0.50 | 0.55 | 0.07 | 0.80 | A ballot with one plausible outcome. |
| military_junta | no | 0.78 | 0.34 | 0.62 | 0.16 | 0.90 | Order by decree, enforced by armour. |
| personalist | no | 0.72 | 0.40 | 0.75 | 0.13 | 0.95 | The state is a person, and the person is tired. |
| one_party_state | no | 0.70 | 0.46 | 0.50 | 0.06 | 0.88 | The Party is the country, the country is the Party. |
| absolute_monarchy | no | 0.60 | 0.52 | 0.58 | 0.09 | 0.85 | Divine right, modern accountancy. |
| const_monarchy | yes | 0.14 | 0.66 | 0.26 | 0.02 | 0.55 | A crown that reigns without ruling. |
| theocratic_state | no | 0.68 | 0.55 | 0.48 | 0.08 | 0.70 | Law descends from a higher court. |
| technocracy | no | 0.45 | 0.53 | 0.30 | 0.07 | 0.85 | Rule by credential and by model. |
| corporate_state | yes | 0.38 | 0.44 | 0.72 | 0.06 | 0.78 | Shareholders are the electorate that counts. |
| failed_state | no | 0.30 | 0.14 | 0.88 | 0.30 | 0.25 | A flag, a capital, and very little else. |
| federal_republic | yes | 0.16 | 0.60 | 0.30 | 0.03 | 0.45 | Sovereignty divided, gridlock included. |
| council_state | yes | 0.35 | 0.50 | 0.35 | 0.09 | 0.50 | Power by assembly, delegate by delegate. |

## Ideologies

All 18 named ideologies, as positions on the six-axis vector (`econ`, `social`, `auth`, `nation`, `milit`, `eco`; each -1..+1). See docs/SYSTEMS.md for what each axis means and how it is used. `appeal` is the audience segment (see `AUDIENCES`) most drawn to it during party formation.

| ideology | appeal | econ | social | auth | nation | milit | eco |
|---|---|---|---|---|---|---|---|
| social_democracy | workers | -0.35 | +0.45 | -0.15 | -0.20 | -0.25 | +0.40 |
| liberalism | urban | +0.45 | +0.45 | -0.45 | -0.45 | -0.15 | +0.15 |
| conservatism | rural | +0.40 | -0.55 | +0.25 | +0.45 | +0.30 | -0.25 |
| national_populism | left_behind | +0.05 | -0.60 | +0.55 | +0.90 | +0.45 | -0.35 |
| socialism | workers | -0.85 | +0.55 | +0.10 | -0.35 | -0.20 | +0.35 |
| market_radical | capital | +0.95 | +0.10 | -0.55 | -0.10 | +0.05 | -0.55 |
| technocracy | professional | +0.25 | +0.35 | +0.55 | -0.30 | +0.10 | +0.35 |
| theocracy | devout | -0.05 | -0.95 | +0.80 | +0.45 | +0.30 | -0.10 |
| militarism | military | +0.10 | -0.45 | +0.85 | +0.75 | +0.95 | -0.35 |
| agrarianism | rural | -0.25 | -0.35 | -0.10 | +0.35 | -0.15 | +0.55 |
| ecologism | youth | -0.40 | +0.60 | +0.05 | -0.45 | -0.55 | +0.98 |
| anarchism | youth | -0.55 | +0.70 | -0.98 | -0.70 | -0.30 | +0.55 |
| monarchism | elite | +0.25 | -0.75 | +0.70 | +0.55 | +0.35 | -0.05 |
| corporatism | capital | +0.65 | -0.20 | +0.55 | +0.35 | +0.25 | -0.40 |
| accelerationism | professional | +0.70 | +0.65 | +0.30 | -0.55 | +0.20 | -0.30 |
| syndicalism | workers | -0.75 | +0.40 | -0.40 | -0.15 | +0.05 | +0.30 |
| reactionism | devout | +0.30 | -0.95 | +0.65 | +0.70 | +0.55 | -0.45 |
| cosmopolitanism | urban | +0.35 | +0.70 | -0.30 | -0.95 | -0.45 | +0.35 |

## Skills

All 35 player/NPC skills (0..1), grouped by category. Effective skill blends the raw value with the governing attribute: `0.78 * skill + 0.22 * (attribute / 20)`.

| skill | category | governing attribute | description |
|---|---|---|---|
| oratory | social | charisma | Move a crowd. |
| negotiation | social | charisma | Close a deal on your terms. |
| deception | social | cunning | Be believed while lying. |
| intimidation | social | will | Make compliance the easy option. |
| networking | social | charisma | Know someone who knows someone. |
| seduction | social | charisma | Leverage attraction and attention. |
| etiquette | social | perception | Move through elite spaces unremarked. |
| politics | power | cunning | Coalitions, whips, and the art of the vote. |
| law | power | intellect | Statute, loophole, and precedent. |
| bureaucracy | power | intellect | Make the machine move — or jam. |
| diplomacy | power | charisma | Interests dressed as principle. |
| propaganda | power | cunning | Author what people believe happened. |
| command | power | presence | Men and women die on your word. |
| strategy | power | intellect | See three moves past the board. |
| finance | econ | intellect | Leverage, arbitrage, and other people's money. |
| management | econ | charisma | Turn headcount into output. |
| trade | econ | cunning | Buy the dip in a country's fortunes. |
| engineering | econ | intellect | Build the thing that builds the thing. |
| logistics | econ | intellect | Move mass across distance on schedule. |
| accounting | econ | perception | Hide a river of money in a spreadsheet. |
| tradecraft | covert | cunning | Dead drops, covers, and clean exits. |
| infiltration | covert | dexterity | Be where you should not be. |
| hacking | covert | intellect | Own the machine that owns the record. |
| surveillance | covert | perception | Watch without being watched. |
| forgery | covert | dexterity | Documents that survive scrutiny. |
| interrogation | covert | will | Extract truth, or something like it. |
| assassination | covert | dexterity | Make a death look like anything else. |
| smuggling | covert | cunning | Freight that isn't on the manifest. |
| medicine | self | intellect | Keep bodies working, yours included. |
| science | self | intellect | Push a frontier, publish or bury it. |
| combat | self | dexterity | Survive the two minutes that matter. |
| survival | self | endurance | Weather, wounds, and worse. |
| theology | self | will | Speak with the authority of the eternal. |
| arts | self | presence | Make meaning that people repeat. |
| languages | self | intellect | Hear what is said when they think you can't. |

## Personality traits

All 26 traits. Every new character (player or NPC) draws 2-4 at random; the player specifically draws 3. `mods` are the mechanical modifiers applied wherever that key is consulted (skill bonuses, stress gain, AP, etc.).

| trait | tags | modifiers |
|---|---|---|
| ambitious | mixed | ap +0.08, ally_fear +0.15 |
| ascetic | light | bribe_taking -0.50, stress_gain -0.10 |
| brave | light | combat +0.10, fear -0.30 |
| charismatic | light | oratory +0.14 |
| charming | light | networking +0.12, seduction +0.10 |
| compassionate | light | legitimacy +0.08, intimidation -0.15 |
| cowardly | dark | fear +0.35, combat -0.10 |
| cynical | dark | morale_effect -0.10, deception +0.08 |
| erratic | dark | variance +0.40 |
| greedy | dark | bribe_taking +0.35 |
| hedonist | mixed | stress_relief +0.25, scandal +0.25 |
| loyal | light | betray_chance -0.40 |
| magnetic | light | recruit +0.20 |
| manipulative | dark | deception +0.14, trust_decay +0.10 |
| meticulous | light | forgery +0.12, accounting +0.10, speed -0.10 |
| obsessive | mixed | research +0.15, stress_gain +0.20 |
| paranoid | dark | surveillance +0.12, stress_gain +0.25 |
| patient | light | stress_gain -0.20, strategy +0.08 |
| principled | light | legitimacy +0.10, deception -0.15 |
| reckless | dark | risk +0.30, combat +0.08 |
| ruthless | dark | intimidation +0.10, empathy -0.25 |
| secretive | mixed | exposure -0.20, networking -0.08 |
| stoic | light | will_check +0.10, stress_gain -0.15 |
| vengeful | dark | loyalty_decay +0.15 |
| visionary | light | science +0.10, propaganda +0.08 |
| workaholic | mixed | ap +0.15, health_decay +0.12 |

## Character backgrounds

All 12 starting backgrounds. `wealth` is starting cash. `attrs` lists attribute bonuses applied before the ±1..2 random jitter every new character gets. `perks` are permanent, background-defining abilities (see the perk glossary below). `notoriety` seeds starting fame, public profile and personal protection.

| background | wealth | attribute bonuses | starting skills | perks | notoriety |
|---|---|---|---|---|---|
| Dynastic Heir | $140M | charisma +1, presence +2 | etiquette 0.45, networking 0.42, finance 0.40, politics 0.30 | old_money, family_seat | 0.18 |
| Burned Operative | $900K | cunning +2, perception +2, dexterity +1 | tradecraft 0.62, surveillance 0.50, infiltration 0.48, combat 0.40, languages 0.40, forgery 0.35 | ghost_identity, old_network | 0.05 |
| Tech Founder | $48M | intellect +3 | engineering 0.55, management 0.45, finance 0.42, hacking 0.38, science 0.35 | engineer_mind, capital_access | 0.22 |
| Sidelined General | $2.4M | will +2, presence +2, endurance +1 | command 0.66, strategy 0.55, combat 0.45, logistics 0.42, intimidation 0.40 | officer_corps, war_college | 0.28 |
| Movement Demagogue | $1.1M | charisma +3, presence +2 | oratory 0.68, propaganda 0.55, politics 0.45, networking 0.40, deception 0.38 | mass_following, media_gravity | 0.44 |
| Shadow Banker | $310M | intellect +2, cunning +2 | finance 0.72, accounting 0.58, trade 0.50, negotiation 0.45, law 0.35 | dark_pools, regulator_friends | 0.12 |
| Syndicate Underboss | $26M | cunning +2, will +2 | smuggling 0.62, intimidation 0.55, networking 0.45, combat 0.42, deception 0.40, accounting 0.35 | underworld_ties, muscle | 0.38 |
| Heretic Scientist | $420K | intellect +4 | science 0.75, engineering 0.48, medicine 0.42, hacking 0.35, bureaucracy 0.25 | lab_access, peer_respect | 0.08 |
| Schismatic Cleric | $680K | will +3, charisma +2 | theology 0.70, oratory 0.55, networking 0.42, propaganda 0.40, etiquette 0.30 | flock, sanctuary | 0.30 |
| Investigative Journalist | $180K | perception +3, intellect +1 | surveillance 0.52, networking 0.50, propaganda 0.45, languages 0.38, deception 0.35, law 0.28 | sources, byline | 0.20 |
| Career Diplomat | $1.6M | charisma +2, intellect +1, perception +1 | diplomacy 0.68, languages 0.55, etiquette 0.50, negotiation 0.48, bureaucracy 0.40, politics 0.38 | chancery_keys, immunity | 0.14 |
| Nobody At All | $9K | — | survival 0.35, deception 0.25 | clean_slate, underestimated | 0.00 |

### Background blurbs

- **Dynastic Heir** (`heir`) — Old money, older obligations. You inherited a name people already fear.
- **Burned Operative** (`operative`) — Fifteen years in the field, then a file with your name on it. Now you freelance.
- **Tech Founder** (`founder`) — You sold the company. The money is real. The itch that made you build it is worse.
- **Sidelined General** (`general`) — They gave you a medal and a desk. The army still takes your calls.
- **Movement Demagogue** (`demagogue`) — You have no office, no army, and eleven million people who repeat what you say.
- **Shadow Banker** (`banker`) — You do not own things. You own the debt of everyone who does.
- **Syndicate Underboss** (`criminal`) — Three ports, two ministers, one bad night that made you boss.
- **Heretic Scientist** (`scientist`) — Your last paper was retracted, classified, then quietly implemented.
- **Schismatic Cleric** (`cleric`) — You were excommunicated for saying it out loud. Congregations kept growing.
- **Investigative Journalist** (`journalist`) — You know where eleven bodies are buried. Two of them are metaphors.
- **Career Diplomat** (`diplomat`) — Four postings, three languages, and a very specific understanding of what treaties are for.
- **Nobody At All** (`nobody`) — No file, no fortune, no name worth remembering. That is the entire advantage.

### Perk glossary

| perk | effect |
|---|---|
| byline | You can publish anywhere and be believed. |
| capital_access | Investors will fund your ventures on a handshake. |
| chancery_keys | Foreign ministries treat you as one of their own. |
| clean_slate | No file anywhere. Investigations start from nothing. |
| cult_of_personality | Your face alone moves public opinion. |
| dark_pools | Move money without leaving a trail regulators can follow. |
| deep_pockets | Bribes cost you 30% less. |
| engineer_mind | Research projects you personally lead run 25% faster. |
| family_seat | A hereditary political seat somewhere in your home nation. |
| flock | Congregations that tithe and turn out. |
| ghost_identity | One spare legend that heat does not attach to. |
| hand_of_god | Assassination attempts against you fail more often. |
| immunity | Diplomatic immunity, until someone bothers to revoke it. |
| iron_stomach | Ruthless acts cost you less stress and less legitimacy. |
| kingmaker | Heads of state owe their position to you. |
| lab_access | A laboratory nobody audits. |
| mass_following | A standing base of supporters that grows with your fame. |
| media_gravity | Everything you do is news, for better and worse. |
| muscle | A standing crew of enforcers who will do violence for you. |
| officer_corps | Serving officers owe you favours; coup odds improve. |
| old_money | Family capital compounds at +3%/yr and opens elite doors. |
| old_network | Start with three placed contacts inside intelligence services. |
| peer_respect | Scientists take your calls and share unpublished work. |
| quantum_ledger | Your finances are effectively unauditable. |
| regulator_friends | Financial investigations against you stall. |
| sanctuary | Religious premises the state hesitates to raid. |
| sources | Secrets surface to you at random. |
| underestimated | Rivals systematically misjudge your reach. |
| underworld_ties | Contraband markets, enforcers, and laundries on call. |
| war_college | Your armies fight above their weight class. |

## Policy levers

All 25 sliders every nation carries (0..1 unless noted), settable directly with the `policy` action once you hold enough authority over a state.

| lever | meaning | min | max | typical default |
|---|---|---|---|---|
| tax_income | Income tax | 0.00 | 0.70 | 0.28 |
| tax_corporate | Corporate tax | 0.00 | 0.60 | 0.22 |
| tax_consumption | Consumption tax | 0.00 | 0.40 | 0.12 |
| tax_wealth | Wealth tax | 0.00 | 0.10 | 0.01 |
| tariff | Average tariff | 0.00 | 0.60 | 0.06 |
| welfare | Welfare spending | 0.00 | 1.00 | 0.35 |
| healthcare | Healthcare spending | 0.00 | 1.00 | 0.40 |
| education | Education spending | 0.00 | 1.00 | 0.42 |
| infrastructure | Infrastructure | 0.00 | 1.00 | 0.38 |
| research | Public R&D | 0.00 | 1.00 | 0.30 |
| military | Defence spending | 0.00 | 1.00 | 0.28 |
| policing | Policing | 0.00 | 1.00 | 0.35 |
| surveillance | Surveillance | 0.00 | 1.00 | 0.25 |
| censorship | Censorship | 0.00 | 1.00 | 0.15 |
| immigration | Immigration openness | 0.00 | 1.00 | 0.45 |
| environment | Environmental regulation | 0.00 | 1.00 | 0.28 |
| labour_rights | Labour protections | 0.00 | 1.00 | 0.45 |
| market_reg | Market regulation | 0.00 | 1.00 | 0.42 |
| capital_control | Capital controls | 0.00 | 1.00 | 0.18 |
| subsidy_energy | Energy subsidy | 0.00 | 1.00 | 0.20 |
| subsidy_farm | Agricultural subsidy | 0.00 | 1.00 | 0.25 |
| space_program | Space programme | 0.00 | 1.00 | 0.08 |
| intel_budget | Intelligence budget | 0.00 | 1.00 | 0.22 |
| propaganda | State messaging | 0.00 | 1.00 | 0.18 |
| conscription | Conscription | 0.00 | 1.00 | 0.10 |

## Criminal rackets

All 10 lines of business a player-controlled syndicate can run with `racket <syndicate> | <kind>`. `margin` is profit share of revenue; `heat` drives how fast police attention accumulates; `violence` and `cap` (capacity ceiling) are flavour/scaling parameters.

| racket | margin | heat | violence | cap | skill | description |
|---|---|---|---|---|---|---|
| smuggling | 0.55 | 0.10 | 0.15 | 1.0 | smuggling | Untaxed goods across a border that leaks. |
| protection | 0.70 | 0.14 | 0.40 | 0.5 | intimidation | A tax on businesses that the state fails to protect. |
| fraud | 0.62 | 0.12 | 0.02 | 0.9 | accounting | Invoices, shells, and vanishing counterparties. |
| cybercrime | 0.68 | 0.16 | 0.02 | 1.2 | hacking | Ransom, theft, and access resold by the hour. |
| gunrunning | 0.58 | 0.28 | 0.35 | 1.1 | smuggling | Small arms into places where they change governments. |
| counterfeit | 0.52 | 0.11 | 0.05 | 0.8 | forgery | Goods, documents, and currency that pass at a glance. |
| laundering | 0.22 | 0.09 | 0.03 | 2.0 | finance | Wash other people's money for a percentage. |
| extortion | 0.75 | 0.22 | 0.45 | 0.4 | intimidation | Leverage applied to individuals with something to lose. |
| black_market | 0.48 | 0.13 | 0.12 | 1.3 | trade | Sanctioned goods, at sanctioned-goods prices. |
| bribery_net | 0.35 | 0.08 | 0.02 | 1.5 | networking | An organised market in official decisions. |

## Treaty kinds

| kind | description | relation bump |
|---|---|---|
| trade | Tariff reduction and market access. | +0.10 |
| defence | An attack on one is an attack on all. | +0.25 |
| nonaggression | Neither party initiates hostilities. | +0.12 |
| alliance | Full military and political alignment. | +0.32 |
| arms_control | Caps and inspections on strategic systems. | +0.15 |
| extradition | Fugitives are handed over on request. | +0.08 |
| intel_share | Reciprocal access to collection product. | +0.18 |
| currency_peg | One currency anchors to the other. | +0.14 |
| customs_union | A shared external tariff wall. | +0.22 |
| vassalage | Foreign policy is set in another capital. | +0.30 |
| basing | Foreign forces stationed on national soil. | +0.20 |
| climate | Binding emissions commitments. | +0.10 |

## War goals

| goal | description | cost | escalation |
|---|---|---|---|
| annex_region | Take and keep a specific region. | 0.30 | 0.65 |
| regime_change | Replace the government with one of yours. | 0.55 | 0.85 |
| vassalise | Reduce them to a client state. | 0.45 | 0.70 |
| resource_grab | Seize named resource concessions. | 0.25 | 0.50 |
| punitive | Degrade capability, extract concessions, leave. | 0.15 | 0.35 |
| liberate | Detach a region into independence. | 0.30 | 0.55 |
| unify | Absorb the whole state. | 0.60 | 0.90 |
| disarm | Force disarmament and inspections. | 0.28 | 0.60 |
| reparations | Extract a payment schedule. | 0.18 | 0.40 |

## Disease registry

All 10 diseases the SEIR epidemic model (docs/SYSTEMS.md) can seed. `r0` is basic reproduction number, `incub`/`dur` are days in the exposed and infectious compartments, `cfr` is case fatality rate, `season` is the amplitude of seasonal forcing.

| disease | R0 | incubation (d) | infectious (d) | CFR | seasonality |
|---|---|---|---|---|---|
| Seasonal influenza | 1.18 | 2 | 7 | 0.0006 | 0.45 |
| Novel influenza | 2.10 | 3 | 9 | 0.0085 | 0.35 |
| Respiratory pathogen X | 2.90 | 5 | 12 | 0.0120 | 0.20 |
| Viral haemorrhagic fever | 1.70 | 8 | 14 | 0.4200 | 0.05 |
| Cholera | 1.90 | 2 | 6 | 0.0300 | 0.30 |
| Resurgent measles | 8.50 | 10 | 8 | 0.0025 | 0.25 |
| Drug-resistant tuberculosis | 1.05 | 40 | 180 | 0.0850 | 0.05 |
| Vector-borne fever | 1.35 | 6 | 10 | 0.0016 | 0.60 |
| Prion cluster | 0.70 | 300 | 120 | 0.9500 | 0.00 |
| Unattributed novel agent | 3.60 | 6 | 14 | 0.1800 | 0.10 |

