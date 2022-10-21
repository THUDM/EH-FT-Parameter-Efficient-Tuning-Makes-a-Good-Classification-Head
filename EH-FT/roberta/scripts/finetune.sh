#! /bin/bash

# Change for multinode config

CHECKPOINT_PATH='please fill with your checkpoint dir path. example:/home/name/roberta-large'

NUM_WORKERS=1
NUM_GPUS_PER_WORKER=1
MP_SIZE=1

script_path=$(realpath $0)
script_dir=$(dirname $script_path)
main_dir=$(dirname $script_dir)
source $main_dir/config/model_roberta_large.sh
echo $MODEL_TYPE

task_name=$1
seed=$2
gpu=$3
lr=$4
epochs=$5
step1_epochs=$6
type=$7
child_p=$8
step1=$9

OPTIONS_NCCL="NCCL_DEBUG=info NCCL_IB_DISABLE=0 NCCL_NET_GDR_LEVEL=2"
HOST_FILE_PATH="hostfile"
HOST_FILE_PATH="hostfile_single"

dataset_name="$task_name"
if [[ "$task_name" == "wsc" ]]; then
  dataset_name="wsc.fixed"
fi

hf_path="super_glue"
if [[ "$task_name" == "cola" || "$task_name" == "sst2" || "$task_name" == "qqp" || "$task_name" == "mrpc" || "$task_name" == "stsb" || "$task_name" == "mnli" || "$task_name" == "qnli" || "$task_name" == "wnli" ]]; then
    hf_path="glue"
fi
if [[ "$task_name" == "squad" ]]; then
  hf_path="squad"
  dataset_name="plain_text"
fi
if [[ "$task_name" == "squad_v2" ]]; then
  hf_path="squad_v2"
fi
if [[ "$task_name" == "conll2003" ]]; then
  hf_path="conll2003"
fi
if [[ "$task_name" == "emotion" ]]; then
  dataset_name="default"
  hf_path="emotion"
fi
if [[ "$task_name" == "wsc" ]]; then
  dataset_name="wsc.fixed"
fi

en_data="hf://${hf_path}/${dataset_name}/train"
eval_data="hf://${hf_path}/${dataset_name}/validation"

if [[ "$task_name" == "semeval2014" ]]; then
  en_data="hf://Yaxin!SemEval2014Task4Raw/restaurants/train"
  eval_data="hf://Yaxin!SemEval2014Task4Raw/laptops/train"
fi


config_json="$script_dir/ds_config_${seed}.json"

finetune_type="$type"

gpt_options=" \
       --finetune-type ${finetune_type} \
       --name-model $MODEL_TYPE \
       --experiment-name finetune-$MODEL_TYPE-${task_name}-${finetune_type}-lr${lr}-seed${seed} \
       --summary-dir runs/finetune-$MODEL_TYPE-${task_name}-${finetune_type} \
       --cls-number 1 \
       --collect-len 2 \
       --model-parallel-size ${MP_SIZE} \
       --mode finetune \
       --epochs ${epochs} \
       --resume-dataloader \
       $MODEL_ARGS \
       --train-data ${en_data} \
       --distributed-backend nccl \
       --lr-decay-style linear \
       --fp16 \
       --save checkpoints/ \
       --split 1 \
       --save-interval 4000 \
       --eval-batch-size 32 \
       --num-workers 0 \
       --warmup 0.1 \
       --valid-data ${eval_data} \
       --strict-eval \
       --dataset-name ${task_name} \
       --warmup 0.1 \
       --seed ${seed} \
       --save-args \
"



if [[ "$task_name" == "wsc" ]]; then
  gpt_options="${gpt_options}
         --checkpoint-activations \
         --checkpoint-num-layers 12 \
  "
fi


#ffadd part
gpt_options="${gpt_options}
        --ffadd-r 32 \
"

#2step xxx
STEP1LR="5e-4"
if [[ "$finetune_type" == "2step+lora" || "$finetune_type" == "2step+ffadd" ]]; then
  STEP1LR="5e-4"
fi

if [[ "$finetune_type" == "2step+pt" ]]; then
  STEP1LR="5e-3"
fi

if [[ "$finetune_type" == "2step+head" ]]; then
  STEP1LR="1e-3"
fi

echo $STEP1LR
gpt_options="${gpt_options}
        --step1-lr ${STEP1LR} \
        --step1-epochs ${step1_epochs} \
"


#child part
gpt_options="${gpt_options}
       --child-type ChildTuning-D \
       --reserve-p ${child_p} \
       --max-grad-norm 1.0 \
"

#load head part
# --head-load \
gpt_options="${gpt_options}
       --head-path  /xxx/xxx \
"

gpt_options="${gpt_options}
       --deepspeed \
       --deepspeed_config ${config_json} \
"

((port=$RANDOM+10000))

#if [ "$FINETUNE_GPU" ]; then
#  echo "use gpu $FINETUNE_GPU"
#else
#  export FINETUNE_GPU=0
#  echo "use gpu $FINETUNE_GPU"
#fi

run_cmd="${OPTIONS_NCCL} deepspeed --include=localhost:${gpu} --master_port ${port} --hostfile ${HOST_FILE_PATH} finetune_roberta.py ${gpt_options}"
echo ${run_cmd}
eval ${run_cmd}
set +x