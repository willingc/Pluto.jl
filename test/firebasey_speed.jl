import Pluto
import Pluto: Cell, ServerSession, Notebook, FunctionName, ClientRequest
import Pluto.Firebasey
import Pluto.WorkspaceManager

using UUIDs
using BenchmarkTools


macro btimed(args...)
    quote
        @btime $(args...)
        nothing
    end
end

s = Pluto.ServerSession()

url = "https://raw.githubusercontent.com/fonsp/disorganised-mess/master/big_images.jl"
urld = "https://raw.githubusercontent.com/fonsp/disorganised-mess/master/big_images_disabled.jl"
nb = Pluto.SessionActions.open_url(s, url; run_async=false)
nbd = Pluto.SessionActions.open_url(s, urld; run_async=false)
nb_success = !any(c.errored for c in nb.cells)

state = Pluto.notebook_to_js(nb)
stated = Pluto.notebook_to_js(nbd)



diff = Firebasey.diff(state, stated)

# @btime Firebasey.diff(state, stated)

nb.bonds = nbd.bonds = Dict(
    :x => Pluto.BondValue(200)
)


@btime Pluto.set_bond_value_reactive(
    session=s,
    notebook=nb,
    name=:x,
    is_first_value=false,
    run_async=false,
)
# 3.261 ms (4003 allocations: 309.61 KiB)

@btime Pluto.set_bond_value_reactive(
    session=s,
    notebook=nbd,
    name=:x,
    is_first_value=false,
    run_async=false,
)
# 3.461 ms (3995 allocations: 309.45 KiB)


fake_clients = [
    Pluto.ClientSession(Symbol("client",i), nothing)
    for i in 1:100
]

function connect(client, notebook)
    s.connected_clients[client.id] = client
    client.connected_notebook = notebook
end

connect(fake_clients[1], nb)
connect(fake_clients[100], nbd)

@time Pluto.set_bond_value_reactive(
    session=s,
    notebook=nb,
    name=:x,
    is_first_value=false,
    run_async=false,
)
# first run:
# 0.817968 seconds (2.60 M allocations: 437.661 MiB, 3.47% gc time)

# second run:
# 0.112966 seconds (5.76 k allocations: 305.899 MiB, 6.51% gc time)




@btime Pluto.set_bond_value_reactive(
    session=s,
    notebook=nb,
    name=:x,
    is_first_value=false,
    run_async=false,
)

# bench:
# 46.573 ms (5717 allocations: 305.89 MiB)

@btime Pluto.set_bond_value_reactive(
    session=s,
    notebook=nbd,
    name=:x,
    is_first_value=false,
    run_async=false,
)
# bench: D
# 3.802 ms (5364 allocations: 462.47 KiB)



@btime Pluto.notebook_to_js(nb)
# 73.542 μs (886 allocations: 77.84 KiB)

@btime let
    new_state = Pluto.notebook_to_js(nb)
    Firebasey.diff(state, new_state)
end
# 126.375 μs (1134 allocations: 91.88 KiB)






# DIGGING INTO set_bond_value_reactive

session = s
notebook = nb
bound_sym = name = :x
new_value = 200
is_first_value = true
@btime Pluto.is_assigned_anywhere(notebook, notebook.topology, bound_sym)
# ns
eq_tester = :(try !ismissing($bound_sym) && ($bound_sym == $new_value) catch; false end) # not just a === comparison because JS might send back the same value but with a different type (Float64 becomes Int64 in JS when it's an integer.)


@btime WorkspaceManager.eval_fetch_in_workspace((session, notebook), eq_tester)
# 385.250 μs (64 allocations: 2.91 KiB)


@btime Pluto.where_referenced(notebook, notebook.topology, Set{Symbol}([bound_sym]))

to_reeval = Pluto.where_referenced(notebook, notebook.topology, Set{Symbol}([bound_sym]))


@btime Pluto.update_save_run!(session, notebook, to_reeval; save=false, persist_js_state=true)
# 44.987 ms (5570 allocations: 305.89 MiB)

old = notebook.topology
new = Pluto.updated_topology(old, notebook, to_reeval)

@btimed Pluto.run_reactive!(session, notebook, old, new, to_reeval)
# 45.323 ms (5403 allocations: 305.87 MiB)



############## GETTING CLOSER


@btimed Pluto.send_notebook_changes!(ClientRequest(session=session, notebook=notebook))
# 12.852 ms (1344 allocations: 101.93 MiB)


@btimed Pluto.send_notebook_changes!(ClientRequest(session=session, notebook=nbd))
# 223.500 μs (1234 allocations: 122.02 KiB)


##### DIGGING DEEPER

notebook_dict = Pluto.notebook_to_js(nb)
client = fake_clients[1]

current_dict = get(Pluto.current_state_for_clients, client, :empty)

Firebasey.use_triple_equals_for_arrays[] = true
patches = Firebasey.diff(current_dict, notebook_dict)
@btimed Firebasey.diff(current_dict, notebook_dict)
# 6.966 ms (48 allocations: 3.75 KiB)

@btime patches_as_dicts::Array{Dict} = patches



using Serialization



Serialization.serialize("/Users/fons/Downloads/example_notebook.jlstate", Pluto.notebook_to_js(nbd))