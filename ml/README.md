# Motor de composição local (ML)

Workspace para treinar o modelo de linguagem pequeno que vai substituir as regras do `RuleEngine` como motor de composição do app (geração de fusões e sugestões, reordenamento por relevância). Tudo roda neste Mac, sem custo por token, e o modelo final roda no iPad.

## Decisões

- **Modelo:** `Qwen/Qwen3-0.6B`, multilíngue, com bom português, cerca de 1,2 GB em bf16 e cerca de 350 MB quantizado em 4 bits.
- **Ajuste:** LoRA com `mlx-lm`. O caminho de adapters do Apple Foundation Models foi encerrado no OS 27, por isso a escolha de um modelo aberto.
- **Execução no iPad:** MLX Swift (`mlx-swift-lm`), por trás do protocolo `CompositionEngine` do app. Só entra no app depois que o modelo passar na avaliação. O simulador renderiza Metal (a atmosfera do app usa um shader), mas o MLX não é suportado nele, e latência e memória do simulador refletem o Mac, não o iPad. Por isso a validação de desempenho exige iPad físico.
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
python3 -m mlx_lm lora -c lora.yaml        # treino → adapters/qwen3-0.6b-r2
python3 evaluate.py --split test --adapter adapters/qwen3-0.6b-r2 --name lora-r2-test
python3 evaluate.py --split parity --adapter adapters/qwen3-0.6b-r2 --name lora-r2-parity
python3 evaluate_jev.py --variant regras --tune-split valid --name jev-regras   # requer TYPESAFE_API_KEY em ../.env
```

Para empacotar para o iPad, quando passar na avaliação:

```sh
python3 -m mlx_lm fuse --model Qwen/Qwen3-0.6B --adapter-path adapters/qwen3-0.6b-r2 --save-path models/composer
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

### Rodada 2, 16/10/2026: núcleo palavra + palavra, 1.900 iterações × 8 (≈ 2 épocas)

Dataset novo:
- todas as fusões palavra + palavra, sobreamostradas 6×;
- os 11 casos de paridade entram no treino;
- 25% de negativos.

Val loss: 4,05 → 0,034, com mínimo de 0,027 na iteração 1750. O treino levou cerca de 1 h no M4.

### Comparativo: Jev × Qwen r1 × Qwen r2 (teste novo, 400 exemplos)

O Jev (TypeSafe, `evaluate_jev.py`) só decide sim/não por par, com limiares calibrados em `valid`. As zonas dele são calculadas em código a partir dessas decisões. Ele não gera texto.

| Métrica | Jev regras | Jev livre | Qwen r1 | Qwen r2 |
| --- | --- | --- | --- | --- |
| Válido/inválido certo | 90,3% | 84,7% | 68,0% | **97,0%** |
| Fusões válidas aceitas | 94,4% | 95,3% | 61,1% | **100%** |
| Pares inválidos rejeitados | 75,8% | 47,0% | **92,4%** | 86,4% |
| Resultado e sugestões exatos | — | — | 67,7% | **97,0%** |
| Palavras na zona certa | 68,3% | 56,7% | 74,5% | **80,7%** |
| Atmosfera exata | 32% | 1% | 39% | **53%** |
| Paridade com o app (11 regras) | — | — | 27,3% | 90,9%¹ |
| Latência por chamada | ~370 ms (remoto) | ~370 ms | 646 ms² | 751 ms² |
| Custo | ~US$ 0,012 / 400 | similar | 0 | 0 |

¹ Na rodada 2 a paridade entrou no treino, então é checagem de memorização, não generalização. A única falha é justamente o passo básico: “eu” + “querer” → “Eu quero ver” (esperado “Eu quero”, com sugestões ir/brincar).
² Mac M4, bf16, sem quantização, um exemplo por vez. A variação entre execuções é grande (a rodada 1 mediu 439 ms antes); medir de novo no iPad.

**Diagnóstico**
- A rodada 2 resolveu o viés para `null`: todas as fusões válidas saem certas, com sugestões exatas.
- A rejeição de inválidos caiu de 92% para 86% com a redução dos negativos para 25%. O próximo dataset deve incluir negativos difíceis (ver `future-HANDOFF.md`, 4.4).
- A **atmosfera** continua o ponto fraco. Gerar as zonas como JSON faz o modelo repetir palavras, inventar outras (“nós” no lugar de “você”) e omitir algumas. Isso apoia a proposta do `future-HANDOFF.md` (camada C): calcular as zonas a partir de um score de validade por par, em vez de gerar listas.
- O Jev é útil como juiz de validade offline (aceita bem os pares válidos, mas rejeita mal os inválidos). Ele não gera fusões e, por ser remoto e por token, não entra no app.

**Próximo passo:** integrar o adaptador r2 como `LocalModelEngine` só para fusões, mantendo as zonas pelo `RuleEngine`. Medir a latência no iPad físico (Fase 0 do `future-HANDOFF.md`).

O app continua usando o `RuleEngine`.
