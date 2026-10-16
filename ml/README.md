# Motor de composição local (ML)

Workspace para treinar o modelo de linguagem pequeno que vai substituir as regras do `RuleEngine` como motor de composição do app (geração de fusões e sugestões, reordenamento por relevância). Tudo roda neste Mac, sem custo por token, e o modelo final roda no iPad.

## Decisões

- **Modelo:** `Qwen/Qwen3-0.6B`, multilíngue, com bom português, cerca de 1,2 GB em bf16 e cerca de 350 MB quantizado em 4 bits.
- **Ajuste:** LoRA com `mlx-lm`. O caminho de adapters do Apple Foundation Models foi encerrado no OS 27, por isso a escolha de um modelo aberto.
- **Execução no iPad:** MLX Swift (`mlx-swift-lm`), por trás do protocolo `CompositionEngine` do app. Só entra no app depois que o modelo passar na avaliação. O simulador não roda Metal, então a validação de desempenho exige iPad físico.
- **Dados:** gerados a partir de uma gramática de C.A. em pt-BR (`vocabulary.json`) que reproduz as regras atuais do app como subconjunto. Uma asserção em `build_dataset.py` garante a paridade. **Revise o vocabulário antes de treinar a sério.**

## Tarefas e formato

Um único modelo, duas tarefas, em JSONL de chat (`system`, `user`, `assistant`). O prompt do sistema está em `build_dataset.py`.

| Tarefa | Entrada (user) | Saída (assistant) |
| --- | --- | --- |
| fusão | `fusao: "Quero ir" + "agora"` | `{"resultado":"Quero ir agora","sugestoes":["perto","longe"]}` ou `{"resultado":null}` |
| atmosfera | `atmosfera: foco "Quero ir"; palavras: ["agora", "comer", "eu"]` | `{"1":["agora","eu"],"2":[],"3":["comer"]}` |

As zonas seguem a regra do app:
1. a palavra combina com o foco;
2. combina com outra palavra presente;
3. não tem combinação.

Na inferência, o prompt usa o template do Qwen3 com `enable_thinking=False`, que é prefixo exato do texto de treino.

## Comandos

```sh
cd ml
pip install -r requirements.txt            # já satisfeito nesta máquina
python3 build_dataset.py                   # data/{train,valid,test,parity}.jsonl
python3 evaluate.py --split test --limit 200 --name base         # modelo base
python3 -m mlx_lm lora -c lora.yaml        # treino → adapters/qwen3-0.6b
python3 evaluate.py --split test --adapter adapters/qwen3-0.6b --name lora
python3 evaluate.py --split parity --adapter adapters/qwen3-0.6b --name lora-parity
```

Para empacotar para o iPad, quando passar na avaliação:

```sh
python3 -m mlx_lm fuse --model Qwen/Qwen3-0.6B --adapter-path adapters/qwen3-0.6b --save-path models/composer
python3 -m mlx_lm convert --hf-path models/composer --mlx-path models/composer-4bit -q --q-bits 4
```

`results/` guarda as métricas de cada avaliação e o log de treino.

## Métricas (`evaluate.py`)

- **Fusão:**
  - JSON válido;
  - resultado exato, incluindo `null` para pares inválidos;
  - resultado e sugestões exatos;
  - acerto separado para pares válidos e inválidos.
- **Atmosfera:** palavras na zona certa e respostas totalmente exatas.
- **Latência:** ms por chamada e tokens/s neste Mac (M4). No iPad, é preciso medir de novo.

## Integração planejada no app

`LocalModelEngine: CompositionEngine` vai responder a `lexicon(for:focus:)` com:
1. uma chamada de **atmosfera** (zonas e, sem foco, a escolha do foco);
2. chamadas de **fusão** para o foco × palavras da zona 1, já que os gestos só armam pares conhecidos.

O `RuleEngine` continua como fallback. O app descarta léxicos que chegam depois que as palavras mudaram.

Pontos em aberto:
- latência total por mudança no iPad;
- agrupar fusões numa só geração;
- tamanho do modelo no bundle ou em Background Assets;
- pares fora do foco (hoje só armam se estiverem no léxico).

## Resultados

### Rodada 1, 16/10/2026: Qwen3-0.6B, LoRA rank 16, 600 iterações × 8 (≈ 0,67 época)

Val loss: 4,26 → 0,041. O treino levou cerca de 15 min no M4.

| Métrica (teste, 400 exemplos) | Base (60 exemplos) | LoRA |
| --- | --- | --- |
| JSON válido | 100% | 100% |
| Fusões válidas corretas | 0% | 64,4% |
| Pares inválidos rejeitados | 0% | 92,0% |
| Palavras na zona certa (atmosfera) | 0% | 73,7% |
| Atmosfera exata | 0% | 39,6% |
| Paridade com as 11 regras do app | 0% | **27,3%** |
| Latência por chamada (Mac M4, bf16) | 582 ms | 439 ms |

**Diagnóstico:** o modelo ficou enviesado para `null`. O dataset tinha só 13 fusões válidas de palavra + palavra (o passo básico, como “querer” + “ir”) contra 3.489 de frase + palavra, por isso a paridade com o app ficou baixa.

**Próxima rodada:**
- incluir todas as fusões palavra + palavra, com sobreamostragem, além dos casos de paridade;
- reduzir os negativos para cerca de 25%;
- treinar de 2 a 3 épocas;
- reavaliar.

O app continua usando o `RuleEngine`.
