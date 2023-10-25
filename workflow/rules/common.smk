from snakemake.utils import validate
import collections
import glob
from pprint import pprint
from pathlib import Path


configfile: "config.yaml"


##### load config and sample sheets #####
def dir_input():
    return Path(config["input_dir"])


def dir_intermediate():
    return Path(config["intermediate_dir"])


def dir_output():
    return config["output_dir"]


# extract sample name from a path
def _get_sample_from_fn(x):
    suffixes = ["fa", "fasta", "fna", "ffa"]

    b = os.path.basename(x)
    if b.endswith(".gz"):
        b = b[:-3]
    sample, _, suffix = b.rpartition(".")
    assert suffix in suffixes, f"Unknown suffix of source files ({suffix} in {x})"
    return sample


# compute main dict for batches
# TODO: if executed in cluster mode, every job will recompute this BATCHES_FN variable when submitted
# TODO: this is because in cluster mode each job is ran as <get the actual snakemake command line if needed>
# TODO: this makes us include this file and thus recompute BATCHES_FN
# TODO: might be a good idea to serialise BATCHES_FN to disk and read from it, instead of recomputing it every time
# TODO: it might hammer the disk in cluster envs, depending on the number of batches
BATCHES_FN = {}
res = dir_input().glob("*.txt")
for x in res:
    b = os.path.basename(x)
    if not b.endswith(".txt"):
        continue
    batch = b[:-4]

    BATCHES_FN[batch] = {}
    with open(x) as f:
        for y in f:
            sample_fn = y.strip()
            if sample_fn:
                sample = _get_sample_from_fn(sample_fn)
                BATCHES_FN[batch][sample] = sample_fn


## WILDCARDS CONSTRAINS
wildcard_constraints:
    sample=r"[a-zA-Z0-9_-]+",
    batch=r"[a-zA-Z0-9_-]+",
    stage=r"(asm|pre|post)",


## BATCHES


def get_batches():
    return BATCHES_FN.keys()


## DIR PATHS


def dir_prophyle(_batch):
    return f"{dir_intermediate()}/post/{_batch}"


def dir_prophyle_propagation(_batch):
    return f"{dir_intermediate()}/post/{_batch}/propagation"


## FILE PATHS


def fn_stats_global():
    return f"{dir_output()}/global_stats.tsv"


def fn_stats_batch_global(_batch):
    return f"{dir_intermediate()}/stats/{_batch}.global.tsv"


def fn_stats_samples(_batch):
    return f"{dir_intermediate()}/stats/{_batch}.samples.tsv"


# *_list - list of files for compression in that order
# *_hist - k-mer histogram
# *_nscl - number of sequence and cumulative length
# *_seq - files with sequences (fa / simpl
# *_compr - compressed dataset


def fn_tree_sorted(_batch):
    return f"{dir_intermediate()}/tree/{_batch}.nw"


def fn_tree_dirty(_batch):
    return f"{dir_intermediate()}/tree/{_batch}.nw_dirty"


def fn_leaves_sorted(_batch):
    return f"{dir_intermediate()}/tree/{_batch}.leaves"


def fn_nodes_sorted(_batch):
    return f"{dir_intermediate()}/tree/{_batch}.nodes"


# Assemblies


def fn_asm_seq_dir(_batch):
    return f"{dir_intermediate()}/asm/{_batch}"


def fn_asm_seq(_batch, _sample):
    return f"{dir_intermediate()}/asm/{_batch}/{_sample}.fa"


def fn_asm_list(_batch):
    return f"{dir_intermediate()}/asm/{_batch}.asm.list"


def fn_asm_hist(_batch):
    return f"{dir_intermediate()}/asm/{_batch}.asm.hist"


def fn_asm_hist_summary(_batch):
    return fn_asm_hist(_batch) + ".summary"


def fn_asm_nscl(_batch):
    return f"{dir_intermediate()}/asm/{_batch}.asm.nscl"


def fn_asm_nscl_summary(_batch):
    return fn_asm_nscl(_batch) + ".summary"


def fn_asm_compr(_batch):
    return f"{dir_output()}/asm/{_batch}.asm.tar.xz"


def fn_asm_compr_summary(_batch):
    return fn_asm_compr(_batch) + ".summary"


# Pre-propagation simplitigs


def fn_pre_seq(_batch, _sample):
    return f"{dir_intermediate()}/pre/{_batch}/{_sample}.simpl"


def fn_pre_list(_batch):
    return f"{dir_intermediate()}/pre/{_batch}.pre.list"


def fn_pre_hist(_batch):
    return f"{dir_intermediate()}/pre/{_batch}.pre.hist"


def fn_pre_hist_summary(_batch):
    return fn_pre_hist(_batch) + ".summary"


def fn_pre_nscl(_batch):
    return f"{dir_intermediate()}/pre/{_batch}.pre.nscl"


def fn_pre_nscl_summary(_batch):
    return fn_pre_nscl(_batch) + ".summary"


def fn_pre_compr(_batch):
    return f"{dir_output()}/pre/{_batch}.pre.tar.xz"


def fn_pre_compr_summary(_batch):
    return fn_pre_compr(_batch) + ".summary"


# Post-propagation simplitigs


def fn_post_seq0(_batch, _node):
    return f"{dir_intermediate()}/post/{_batch}/propagation/{_node}.reduced.fa"


def fn_post_seq(_batch, _node):
    return f"{dir_intermediate()}/post/{_batch}/{_node}.simpl"


def fn_post_list(_batch):
    return f"{dir_intermediate()}/post/{_batch}.post.list"


def fn_post_hist(_batch):
    return f"{dir_intermediate()}/post/{_batch}.post.hist"


def fn_post_hist_summary(_batch):
    return fn_post_hist(_batch) + ".summary"


def fn_post_nscl(_batch):
    return f"{dir_intermediate()}/post/{_batch}.post.nscl"


def fn_post_nscl_summary(_batch):
    return fn_post_nscl(_batch) + ".summary"


def fn_post_compr(_batch):
    return f"{dir_output()}/post/{_batch}.post.tar.xz"


def fn_post_compr_summary(_batch):
    return fn_post_compr(_batch) + ".summary"


## WILDCARD FUNCTIONS


# get source file path
def w_sample_source(wildcards):
    batch = wildcards["batch"]
    sample = wildcards["sample"]
    fn = BATCHES_FN[batch][sample]
    return fn


# get all source files paths for a given batch
def w_batch_asms(wildcards):
    batch = wildcards["batch"]
    l = [fn_asm_seq(batch, sample) for sample in BATCHES_FN[batch]]
    return l


# get pre-propagation simplitig files from batch & sample
def w_batch_pres(wildcards):
    batch = wildcards["batch"]
    l = [fn_pre_seq(batch, sample) for sample in BATCHES_FN[batch]]
    return l


# get post-propagation simplitig files from batch & sample
def w_batch_posts(wildcards):
    _ = checkpoints.prophyle_index.get(**wildcards)
    tr = [
        fn_post_seq(wildcards.batch, node)
        for node in load_list(fn_nodes_sorted(wildcards.batch))
    ]
    return tr


## OTHER FUNCTIONS


# generate file list from a list of identifiers (e.g., leaf names -> assemblies names)
def generate_file_list(input_list_fn, output_list_fn, filename_function):
    with open(input_list_fn) as f:
        with open(output_list_fn, "w") as g:
            for x in f:
                x = x.strip()
                fn0 = filename_function(x)  # top-level path
                fn = os.path.relpath(fn0, os.path.dirname(output_list_fn))
                g.write(fn + "\n")


def load_list(fn):
    try:
        with open(fn) as f:
            return [x.strip() for x in f]
    except FileNotFoundError:
        print(f"File not found {fn}, using empty list")
        return []
