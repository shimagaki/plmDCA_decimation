include("ProcessingTools.jl")

# fam = "PF00014_raw"
fam = ARGS[1]
cd(@sprintf("%s_results",fam))
N = parse(Int64,readstring(pipeline(`head -n 1 msa_numerical.txt`,`awk '{print NF}'`)))
q = 21

# Finding all graphs
list_graph_t = readstring(pipeline(`find . -regextype sed -regex '.*plmInf_\([0-9]\|[0-9][0-9]\)_mat.txt'`,`sort -t"_" -k3n`))
list_graph_t = map(String, split(list_graph_t, "\n")[1:end-1]) # List of all decimated graphs
ld_graph = map(x->parse(Int64,String(match(r"[0-9]*[0-9]",x).match)),list_graph_t) # List of all decimation indices
Kall = size(ld_graph)[1]
y = Array{Float64,1}(0) # Decimated fraction of coupling
for a in ld_graph
	# a = ld_graph[i]
	push!(y,parse(Int64, readstring(pipeline(`wc -l decimation_results/mask$a.txt`,`awk '{print $1}'`))[1:end-1])*2/N/(N-1))
end

# List of inferred graphs which have a sample
list_samples =  readstring(pipeline(`find . -regextype sed -regex '.*sample_\([0-9]\|[0-9][0-9]\).txt'`,`sort -t"_" -k2n`))
list_samples = map(String, split(list_samples, "\n")[1:end-1]) 
ld = map(x->parse(Int64,String(match(r"[0-9]*[0-9]",x).match)),list_samples)
Ks = size(ld)[1]
list_graph = Array{String,1}(0) # List of graphs with a sample
for i = 1:Kall
	if in(ld_graph[i],ld)
		push!(list_graph, list_graph_t[i])
	end
end
println("Decimation indices used for fitting quality & KL-div:\n",ld)

# List of graphs for estimating PL
list_graph_pl = list_graph_t[1:2:end] # List of graphs for computing PL
ld_pl = ld_graph[1:2:end] # List of indices for evaluating PL
Kpl = size(ld_pl)[1]
println("Decimation indices used for Pseudo-likelihood:\n",ld_pl)


# Training sequences
sample_nat = readdlm("msa_numerical.txt", Int64)
(f1_nat,f2_nat) = ReturnFreqs(sample_nat, weights="weights.txt",verbose=false)
wnat = vec(readdlm("weights.txt"))

# Pseudo-likelihood of full and independent models
println("Pseudo-likelihood of full and independent models...")
h_indep = log.(f1_nat + 0.0001)
J_indep = zeros(Float64, N*q, N*q)
(J_full, h_full) = ReadGraph("decimation_results/plmInf_0_mat.txt",N,q)
natT = sample_nat'
PL_indep = PseudoLikelihood(natT, wnat, J_indep, h_indep, q)
PL_full = PseudoLikelihood(natT, wnat, J_full, h_full, q)
PL = zeros(Float64, Kpl)
PL_scaled = zeros(Float64,Kpl)
x = zeros(Float64, Kpl)
println("Pseudo-likelihood of decimated models...")
for i in 1:Kpl
	print("$i/$Kpl... ")
	graph_i = ReadGraphStruct(list_graph_pl[i],N,q)
	a = ld_pl[i]
	x[i] = parse(Int64, readstring(pipeline(`wc -l decimation_results/mask$a.txt`,`awk '{print $1}'`))[1:end-1])*2/N/(N-1)
	@printf("%.3f",x[i])
	print("      \r")
	PL[i] = PseudoLikelihood(natT, wnat, graph_i.J, graph_i.h, q)
	PL_scaled[i] = PL[i] - ((1-x[i])*PL_full + x[i]*PL_indep)
	i+=1
end
println("done.                                     ")

# Fitting quality and pairwise KL-div
println("Fitting quality and pairwise KL-div")
out_kl = zeros(Float64,Ks,Ks)
out_fitqual = zeros(Ks,5)
for i = 1:Ks
	print("i = $i/$Ks      \r")
	# Fitting quality
	sample_i = readdlm(list_samples[i],Int64,skipstart=1)+1
	(f1,f2) = ReturnFreqs(sample_i,verbose=false)
	out_fitqual[i,1] = ld[i]
	(out_fitqual[i,2],out_fitqual[i,3],out_fitqual[i,4],out_fitqual[i,5]) = FittingQuality(f2_nat, f1_nat, f2, f1, q)
	# Pairwise KL-div 
	graph_i = ReadGraphStruct(list_graph[i],N,q)
	for j = (i+1):Ks
		sample_j = readdlm(list_samples[j],Int64,skipstart=1)+1
		graph_j = ReadGraphStruct(list_graph[j],N,q)
		out_kl[i,j] = SymKLDiv(graph_i, graph_j, sample_i, sample_j)[1]
		out_kl[j,i] = out_kl[i,j]
	end
end
println("done.                                      ")

# Saving results
run(`mkdir -p processing_results`)
save_ld = @sprintf("processing_results/%s_samplesteps.txt",fam)
save_kl = @sprintf("processing_results/%s_KLdiv.txt",fam)
save_fitqual = @sprintf("processing_results/%s_fittingquality.txt",fam)
save_PL = @sprintf("processing_results/%s_PL.txt",fam)

# Saving list of decimation indexes
f = open(save_ld,"w")
write(f, "Decimation_index Decimated_fraction\n")
writedlm(save_ld,[ld_graph y])
close(f)
# Saving KLdiv
writedlm(save_kl, out_kl)
# Saving fitting quality
f = open(save_fitqual, "w")
write(f, "Decimation_index CC_fronorm_pears CC_fronorm Mag_pears Mag_fronorm\n")
writedlm(f,out_fitqual, ' ')
close(f)
# Saving values of PL
f = open(save_PL, "w")
write(f, "Decimation_rate PL PL_scaled\n")
writedlm(f,[ld_pl PL PL_scaled],' ')
close(f)

cd("../")
