# Future handoff — prospecção e escalonamento do motor de composição

> **Leitores:** a equipe que assume o projeto e seus agentes de IA. Comece por [docs/ONBOARDING.md](docs/ONBOARDING.md); este documento vem depois, quando o assunto for motor de composição, IA, escala ou idiomas.
>
> **Autoria:** redigido pelo Designer AI Prototyper autor do protótipo, com apoio de agentes de IA. É uma proposta de direção, não um plano de engenharia revisado: a equipe valida, ajusta ou descarta.
>
> **Status:** prospecção. Nada aqui é requisito da v1 nem decisão tomada (ver `AGENTS.md`, “Decisões em aberto”). O documento registra o caminho provável para levar o motor de composição de um laboratório com vocabulário fechado a um produto com alta assertividade sobre o português comum e, depois, outros idiomas. Estimativas de esforço, volume e custo são ordens de grandeza a validar; referências e licenças devem ser conferidas antes do uso.
>
> **Para agentes:** use este documento para responder perguntas de roteiro e para propor trabalho, nunca como especificação a implementar sem decisão da equipe. Ao propor trabalho no motor, comece pela Fase 0 (seção 7) e respeite as restrições da seção 9.

## 1. Ponto de partida (16/10/2026)

- **App:** `CompositionEngine` com `RuleEngine` (regras fechadas em `Vocabulary.swift`). O app consome um `Lexicon` (fusões, foco, zonas) e descarta léxicos desatualizados. O contrato não depende do idioma nem de como o léxico é produzido.
- **`ml/`:** Qwen3-0.6B + LoRA (mlx-lm), dataset gerado por uma gramática de C.A. em pt-BR (`vocabulary.json`) com paridade forçada com o app.
  - Rodada 1: fusões válidas 64,4%, inválidas rejeitadas 92,0%, palavras na zona certa 73,7%, paridade 27,3% (viés para `null`).
  - Rodada 2 (núcleo palavra + palavra sobreamostrado): válido/inválido certo 97,0%, fusões válidas 100% com sugestões exatas, inválidas rejeitadas 86,4%, palavras na zona certa 80,7%. A atmosfera gerada como JSON segue o ponto fraco (repete e inventa palavras). Tabela completa em `ml/README.md`.
- **Jev (TypeSafe), comparativo de decisão** (`ml/evaluate_jev.py`, 400 exemplos de teste, limiares calibrados em `valid`):

  | Variante | Válido/inválido certo | Válidos aceitos | Inválidos rejeitados | Zona certa | Latência | Custo |
  | --- | --- | --- | --- | --- | --- | --- |
  | regras (gramática no estado) | 90,3% | 94,4% | 75,8% | 68,3% | ~370 ms | US$ 0,012 |
  | livre (só “é português natural?”) | 84,7% | — | 47% | 56,7% | ~370 ms | similar |

  O Jev é serviço remoto e por token, então não entra no app (regra do `AGENTS.md`). Ele serve como **juiz offline** na curadoria de dados (seção 4.6).

## 2. Tese: generalizar, não memorizar

O vocabulário atual cabe numa tabela de regras. O vocabulário aberto não cabe:

| Vocabulário | Pares possíveis (n·(n−1)/2) |
| --- | --- |
| 25 palavras (hoje) | 300 |
| 400 lemas (núcleo de C.A.) | ~80 mil |
| 5.000 lemas (fala cotidiana) | ~12,5 milhões |

Mais as frases já fundidas, que também se combinam. Nenhum dataset cobre isso par a par. O modelo precisa aprender **a gramática da composição** e acertar pares que nunca viu, e a avaliação precisa medir exatamente isso: lemas e estruturas fora do treino (seção 6).

## 3. Arquitetura alvo

Dividir o trabalho para que o que pode ser exato seja exato e o LLM fique só com o que exige linguagem.

```
palavras na tela + foco
        │
        ▼
[A] Léxico morfológico ──► lemas, classes, flexões possíveis, gênero/número
        │
        ▼
[B] Ranking de relevância (embeddings + coocorrência) ──► top-k candidatos por foco
        │
        ▼
[C] Validade: P(par funde) num só forward do LLM (log-prob de resultado ≠ null), em lote
        │                      └─► zonas = limiares calibrados sobre P (1 alta, 2 média, 3 baixa)
        ▼
[D] Geração (LLM + decodificação restrita a JSON e ao léxico) ──► resultado + 2 sugestões
        │
        ▼
[E] Verificação: morfologia do resultado confere com [A]; senão, RuleEngine/descarta
        │
        ▼
     Lexicon ──► app (mesmo contrato de hoje)
```

| Camada | Ferramenta | Por quê |
| --- | --- | --- |
| A. Morfologia | Léxico de formas plenas (pt-BR: MorphoBr, DELAF-PB) | Conjugação e concordância não podem errar; tabela acerta sempre e é auditável |
| B. Relevância | Embeddings de sentença/palavra + estatística de coocorrência do corpus | Ranking é barato, roda no aparelho e corta o número de chamadas ao LLM |
| C. Validade e zonas | Probabilidade do próprio LLM ajustado (como o Noul do Jev) | Um score contínuo encaixa no conceito do app: “quanto mais perto do foco, maior a probabilidade de fusão” |
| D. Geração | LLM pequeno ajustado, saída restrita | Fusão com ajuste linguístico e sugestões contrastantes exigem linguagem |
| E. Verificação | Regras + léxico | Rede de segurança; o `RuleEngine` continua como fallback |

**Mudança de semântica a decidir:** hoje a zona é binária (“combina ou não”). No vocabulário aberto ela passa a ser uma **faixa de probabilidade** calibrada. A regra atual vira um caso particular.

**Perfil do usuário:** gênero e número de quem fala já afetam o português (“estou cansado/cansada”) e afetam muito mais o hindi (seção 8.4). O motor precisa receber um perfil mínimo (gênero gramatical preferido, variedade regional), definido pelo usuário ou por quem o acompanha, nunca inferido.

## 4. Dados: o processo que mais pesa na assertividade

### 4.1 Vocabulário-alvo por frequência e função

1. **Núcleo de C.A.** (~400 lemas): pronomes, verbos modais e de ação, negação, tempo, lugar, quantidade, qualificadores, sociais (oi, obrigado, não gosto). A pesquisa em C.A. (sobretudo em inglês) indica que algumas centenas de palavras de vocabulário nuclear cobrem a maior parte do que se diz no dia a dia (Banajee et al., 2003; Project Core). Para pt-BR, levantar listas nacionais de vocabulário nuclear com fonoaudiólogos; na falta delas, adaptar as listas em inglês e validar por frequência em corpus oral.
2. **Vocabulário de fala cotidiana** (~3 a 5 mil lemas), ranqueado por frequência em corpora orais e de legendas.
3. **Vocabulário periférico** (*fringe*): nomes, lugares, comidas, pessoas do usuário. Entra pela personalização (seção 5, T5), não pelo treino global.

### 4.2 Corpora de frases reais

| Fonte | Uso | Observação |
| --- | --- | --- |
| OpenSubtitles (pt-BR) | Fala conversacional em volume | Ruído de tradução; filtrar |
| CHILDES (português) | Fala infantil e dirigida à criança | Próxima do público de C.A. infantil |
| NURC e corpora orais | Fala espontânea adulta | Volume menor, alta qualidade |
| Tatoeba | Frases curtas e limpas | Bom para teste |
| UD Portuguese (Bosque, GSD) | Árvores sintáticas anotadas | Treinar e avaliar o analisador |

Conferir licença de cada corpus para uso em treino comercial antes da Fase 2.

### 4.3 Decomposição de frases reais em fusões

Um analisador de dependências (spaCy ou Stanza) quebra cada enunciado curto em constituintes: sujeito, modal, verbo, complemento, tempo. Cada ordem de montagem vira exemplos de fusão cujo resultado **existe de verdade**:

```
"eu não quero ir agora"
  querer + ir            → "Quero ir"
  "Quero ir" + agora     → "Quero ir agora"
  não + "Quero ir agora" → "Não quero ir agora"
  eu + "Não quero ir…"   → "Eu não quero ir agora"
```

Essa é a principal fonte de positivos. A gramática atual (`vocabulary.json`) vira um gerador complementar para estruturas raras no corpus.

### 4.4 Negativos difíceis

Pares absurdos ensinam pouco. Os que ensinam o limite são quase certos:
- regência errada (“gostar” + “água” → “Gosto água”, sem o “de”);
- complemento incompatível com o verbo (“beber” + “pão”);
- slot duplicado (dois tempos, dois sujeitos);
- concordância impossível com o perfil.

Proporção inicial: ~25% de negativos, como na rodada 2, metade deles difíceis.

### 4.5 Sugestões contrastantes a partir do corpus

Para cada resultado, coletar as continuações mais frequentes no corpus, agrupar por campo semântico (embeddings) e escolher **duas de grupos diferentes**: “agora/depois”, “aqui/lá”, “água/suco”. A regra atual de oposição vira um caso particular de “alto contraste e alta probabilidade”.

### 4.6 Professor + filtros (destilação de dados)

Um modelo grande gera e rotula em escala os casos que o corpus não cobre. Todo exemplo passa por filtros antes de entrar:

1. morfologia confere com o léxico (camada A);
2. o analisador reconhece a estrutura;
3. votação entre juízes independentes: professor, Jev (validade) e modelo da rodada anterior;
4. discordâncias vão para uma **fila de revisão humana**, não para o treino.

Notas:
- O custo é único, na criação do dataset. O app continua sem custo por token.
- Preferir professor de pesos abertos (por exemplo, Qwen3 grande) ou verificar se os termos de uso do provedor permitem treinar com as saídas.
- O Jev, com 90,3% de acerto de validade, serve como filtro e desempate, não como fonte única.

### 4.7 Conjunto ouro

Alguns milhares de casos por idioma, escritos e revisados por fonoaudiólogos e falantes nativos, cobrindo todas as estruturas e o núcleo de C.A. **Nunca entra no treino.** É o portão de cada rodada, como a paridade é hoje.

### 4.8 Dados de uso real (a fonte mais valiosa)

Com consentimento explícito (LGPD/GDPR; responsáveis legais no caso de crianças): fusões aceitas, desfeitas (Undo é um rótulo negativo forte), sugestões tocadas e ignoradas. Por padrão nada sai do aparelho. A coleta é opt-in, anonimizada e restrita a eventos de composição.

### 4.9 Volume por fase (estimativa)

| Fase | Exemplos de treino | Conjunto ouro |
| --- | --- | --- |
| 1. Núcleo de C.A. | 30–50 mil | 1–2 mil |
| 2. Vocabulário aberto | 200–500 mil | 3–5 mil |
| 3. Uso real | + preferências (dezenas de milhares de pares) | revisão contínua |

## 5. Treino em estágios

| Estágio | O quê | Onde | Notas |
| --- | --- | --- | --- |
| T0. Base | Qwen3-1.7B (ou 4B), escolhido por avaliação em pt-BR | — | O 0.6B serve ao laboratório; vocabulário aberto pede mais conhecimento de língua |
| T1. SFT | Fine-tune supervisionado com mistura de tarefas: fusão, rejeição, sugestões, score de validade | Mac (LoRA no 1.7B, a medir) ou GPU na nuvem (fine-tune completo) | LoRA com rank maior (32–64) ou completo; currículo do núcleo para o periférico |
| T2. Preferência | DPO: entre duas fusões ou dois pares de sugestões, qual é mais natural e útil | Mac/nuvem | Preferências vêm de especialistas (Fase 2) e de uso real (Fase 3) |
| T3. Destilação | Professor grande → aluno do tamanho do aparelho | Nuvem | Só se T1 com o modelo pequeno não atingir as metas |
| T4. Quantização | 4 bits, MLX | Mac | Medir a perda no conjunto ouro antes de aceitar |
| T5. Personalização | Reranking local por frequência do usuário + vocabulário periférico; opcionalmente um LoRA pessoal pequeno | iPad | Nunca sai do aparelho |

Tamanhos aproximados em 4 bits: 0.6B ≈ 350 MB, 1.7B ≈ 1 GB, 4B ≈ 2,3 GB. A escolha final depende de latência e memória medidas em iPad físico.

**Metas de latência no aparelho (proposta):**
- validade em lote para todas as palavras da tela: < 300 ms;
- geração de uma fusão: < 400 ms.

A camada B corta os pares antes do LLM para caber nesse orçamento.

## 6. Avaliação

### 6.1 Divisões do teste

| Divisão | Mede | Hoje |
| --- | --- | --- |
| Pares novos de lemas vistos | Composição | É o teste atual |
| **Lemas não vistos** (verbos e substantivos inteiros fora do treino) | Generalização | Falta; criar na Fase 1 |
| Estruturas não vistas (por exemplo, negação + tempo + quantidade) | Generalização sintática | Falta |
| Conjunto ouro | Qualidade real | Falta |
| Paridade com o `RuleEngine` | Regressão do comportamento atual | Existe |

### 6.2 Métricas e metas propostas

| Métrica | Fase 1 | Fase 2 |
| --- | --- | --- |
| Validade (válido/inválido certo), lemas não vistos | ≥ 90% | ≥ 95% |
| Gramaticalidade do resultado (analisador + humano) | ≥ 95% | ≥ 98% |
| Ranking das zonas (NDCG contra o ouro) | ≥ 0,85 | ≥ 0,9 |
| Sugestões úteis (avaliação humana: “eu tocaria nesta”) | ≥ 70% | ≥ 80% |
| Economia de toques para frases-alvo (*keystroke savings*) | medir a linha de base | melhora sobre a Fase 1 |
| Segurança (sugestão não pedida ofensiva ou inadequada) | 0 no ouro | 0 no ouro |

**Taxa de comunicação** (toques e tempo para dizer o que se quer) é a métrica de produto que importa em C.A. (Trnka et al., 2007). As demais são proxies.

**Nuance de segurança:** filtrar **sugestões não solicitadas**, nunca o vocabulário do usuário. Uma pessoa que usa C.A. precisa conseguir dizer qualquer coisa, inclusive dor, raiva, palavrões e relatos de abuso.

### 6.3 Portão de regressão

Uma rodada só substitui a anterior se não piorar no ouro, na paridade e nos lemas não vistos. Cada rodada registra os resultados em `ml/results/` e no `ml/README.md`.

## 7. Roteiro por fases

### Fase 0 — Fechar o laboratório (agora)

- A partir da rodada 2: integrar o adaptador só para fusões e manter as zonas pelo `RuleEngine` até a camada C existir.
- Implementar `LocalModelEngine` com MLX Swift atrás do `CompositionEngine`, medir latência em iPad físico.
- **Saída:** modelo no app sem regressão de paridade e com latência medida.

### Fase 1 — Núcleo de C.A. em pt-BR

- Lista de ~400 lemas validada com fonoaudiólogos.
- Morfologia passa a vir do léxico (camada A); o modelo deixa de conjugar “de cabeça”.
- Perfil mínimo (gênero gramatical, variedade).
- Divisão de lemas não vistos e primeiro conjunto ouro (1–2 mil).
- Score de validade (camada C) substitui a tarefa “atmosfera” gerada em JSON.
- **Saída:** metas da Fase 1 em 6.2. **Esforço estimado:** 4 a 8 semanas de uma pessoa, mais o tempo dos especialistas.

### Fase 2 — Vocabulário aberto em pt-BR

- Pipeline de corpus (4.2–4.5), professor + filtros (4.6), Qwen3-1.7B, 200–500 mil exemplos.
- Embeddings e coocorrência no aparelho (camada B).
- DPO com preferências de especialistas.
- **Saída:** metas da Fase 2. **Esforço estimado:** 2 a 4 meses. Custo de nuvem pontual na ordem de dezenas a centenas de dólares por rodada (a medir).

### Fase 3 — Uso real e personalização

- Estudo com usuários de C.A. (ética, consentimento, responsáveis).
- Coleta opt-in de eventos de composição, DPO com uso real, personalização local.
- **Saída:** melhora mensurável da taxa de comunicação contra a Fase 2.

### Fase 4 — Outros idiomas (seção 8)

- Começar só depois que a Fase 2 provar o pipeline em pt-BR.

## 8. Escalonamento para outros idiomas

### 8.1 O que se reaproveita e o que é por idioma

| Reaproveita (independe do idioma) | Por idioma |
| --- | --- |
| Contrato `CompositionEngine` / `Lexicon` e toda a UI de composição | Léxico morfológico (camada A) |
| Arquitetura A–E e verificação | Lista de vocabulário nuclear |
| Pipeline de decomposição de frases, negativos, sugestões, filtros | Corpora e analisador sintático |
| Métricas, portões, scripts de treino e avaliação | Conjunto ouro com nativos e especialistas locais |
| Modelo base multilíngue (o Qwen3 declara suporte a 119 idiomas e dialetos) | Adaptador LoRA por idioma (um base, vários adaptadores) ou um adaptador multilíngue |
| — | Direção de escrita, fontes e tamanho dos chips na UI |

**Um base, um adaptador por idioma:** o app carrega o base uma vez e troca um adaptador de poucos MB. Um adaptador multilíngue único é tentador, mas mistura erros entre idiomas. Decidir por avaliação.

### 8.2 Inglês: o paralelo completo do treino de assertividade

O inglês é o idioma com **maior viabilidade**: mais dados, mais pesquisa em C.A. e o modelo base mais forte. O mesmo processo das seções 4 a 6, passo a passo:

| Etapa | pt-BR | Inglês |
| --- | --- | --- |
| 4.1 Núcleo de C.A. | Listas nacionais a levantar | Listas consolidadas e estudadas: Banajee et al. (2003), Universal Core do Project Core, Beukelman et al. (1989) |
| 4.2 Corpora | OpenSubtitles, CHILDES pt, NURC | OpenSubtitles, CHILDES (Eng-NA/UK, o maior acervo), Santa Barbara Corpus of Spoken American English |
| Morfologia (camada A) | MorphoBr, DELAF-PB | UniMorph (eng), LemmInflect; a morfologia é pobre (`-s`, `-ed`, `-ing`) |
| Analisador | spaCy/Stanza pt, UD Bosque | spaCy/Stanza en, UD English EWT; os mais maduros que existem |
| 4.6 Professor + filtros | Igual | Igual; os juízes (inclusive o Jev, que recomenda instruções em inglês) tendem a ser mais precisos |
| 4.7 Conjunto ouro | Fonoaudiólogos BR | SLPs (*speech-language pathologists*); a comunidade de pesquisa em C.A. é sobretudo anglófona |
| 6.2 Métricas | Igual | Igual; existe literatura de *keystroke savings* para comparar |

**O que muda na gramática da fusão:** o inglês exige **palavras funcionais** que o chip não tem. O português já faz isso em parte (“gostar” + “ir” → “Gosto **de** ir”), então a regra do motor deve ser “pode inserir palavras funcionais, nunca palavras de conteúdo”:
- *want* + *go* → “I want **to** go” (infinitivo com *to*), mas *can* + *go* → “I can go”;
- negação com *do-support*: *not* + “I want to go” → “I **don’t** want to go”;
- terceira pessoa (*she want**s***), contrações (*don’t*, *I’d like*) e polidez (*want* vs *would like*), que vira um bom par de sugestões contrastantes;
- ordem rígida de sujeito, verbo e objeto e verbos frasais (*go out*, *pick up*) que se comportam como um só chip.

**Viabilidade:** alta. Reaproveita a maior parte do pipeline. O gargalo é o conjunto ouro com nativos e SLPs, não os dados. **Mercado:** é o maior mercado de C.A., mas também o mais maduro (Proloquo2Go, TD Snap, TouchChat). O diferencial a provar é a composição por manipulação direta, não o vocabulário.

### 8.3 Espanhol

- **Falantes:** ~560 milhões (L1 + L2; Ethnologue, ordem de grandeza).
- **Facilita:** é o idioma mais próximo do português. Conjugação rica mas regular, ordem flexível semelhante, sujeito omissível (“quiero ir”). O pipeline e até parte das regras transferem quase 1:1. Bons recursos: UD Spanish (AnCora, GSD), CHILDES espanhol, UniMorph (spa), OpenSubtitles.
- **Dificulta:** variação regional de tratamento (*tú*, *vos*, *usted*) e de vocabulário (México, Argentina, Espanha), que precisa entrar no perfil; clíticos pospostos ao verbo (“quiero comer**lo**”) e subjuntivo em estruturas comuns (“quiero que **vengas**”).
- **Dificuldade de treino: baixa.** Melhor custo-benefício como segundo idioma junto com o inglês.

### 8.4 Mandarim

- **Falantes:** ~1,2 bilhão (L1 + L2).
- **Facilita:** quase não há flexão: “我想去” (*wǒ xiǎng qù*, “quero ir”) não conjuga nada. O Qwen é especialmente forte em chinês, e há muitos dados (CHILDES mandarim, UD Chinese, legendas).
- **Dificulta:**
  - não há espaços entre palavras, então “o que é um chip” é uma decisão de produto (palavra segmentada, caractere ou expressão) e o pipeline exige segmentação;
  - **classificadores** obrigatórios em quantidades (“一**杯**水”, um *copo de* água; “一**个**苹果”, uma maçã), que a fusão de quantidade precisa escolher;
  - partículas de aspecto (了, 过, 着) no lugar de tempos verbais, com sutileza de uso;
  - escrita simplificada vs tradicional e exibição com ou sem pinyin, que afetam a legibilidade e o tamanho dos chips.
- **Dificuldade de treino: média.** Morfologia trivial, mas a estrutura e a escrita pedem decisões novas de produto e de dados.

### 8.5 Hindi

- **Falantes:** ~610 milhões (L1 + L2).
- **Facilita:** muitos falantes e recursos crescentes (UD Hindi HDTB, IndicCorp, ferramentas da AI4Bharat).
- **Dificulta:**
  - **o verbo concorda em gênero com o falante:** “मैं जाना चाहता हूँ” (*main jānā chāhtā hūn*, homem) vs “चाहती हूँ” (*chāhtī*, mulher). O perfil do usuário é obrigatório, não opcional;
  - construção ergativa no passado perfectivo (“मैंने खाया”, o verbo passa a concordar com o objeto);
  - ordem sujeito-objeto-verbo e posposições, o que muda a montagem incremental da frase;
  - escrita devanágari com conjuntos de consoantes; a fala real mistura inglês (*Hinglish*), muitas vezes escrito em alfabeto latino;
  - menos dados conversacionais limpos e menos pesquisa em C.A.; tokenizadores tendem a gastar mais tokens por palavra (latência a medir).
- **Dificuldade de treino: alta.**

### 8.6 Árabe

- **Falantes:** ~330 milhões para o árabe padrão moderno (L2 na maioria); o árabe como macrolíngua passa de 400 milhões.
- **Facilita:** recursos de NLP maduros para o padrão moderno (CAMeL Tools para morfologia, UD Arabic PADT) e corpus paralelo de dialetos (MADAR).
- **Dificulta:**
  - **diglossia:** escreve-se o padrão moderno, mas fala-se o dialeto (egípcio, levantino, do Golfo, magrebino). Um app de C.A. precisa falar o dialeto do usuário, e há pouco dado dialetal. Cada dialeto é quase um idioma de produto;
  - morfologia de raiz e padrão, com clíticos colados (“وسأكتبها”, *e vou escrevê-la*, é uma só palavra), dual e concordância de gênero inclusive na segunda pessoa;
  - vogais curtas geralmente omitidas na escrita, o que gera ambiguidade para leitura e para voz;
  - escrita da direita para a esquerda: a UI espelha (zonas, ordem de leitura dos chips, direção da composição) e o texto exige ligaduras.
- **Dificuldade de treino: muito alta.** Começar por um único dialeto com parceiros locais.

### 8.7 Comparativo de dificuldade (1 = fácil, 5 = difícil, para esta tarefa)

| Dimensão | pt-BR | Inglês | Espanhol | Mandarim | Hindi | Árabe |
| --- | --- | --- | --- | --- | --- | --- |
| Morfologia e concordância | 3 | 1 | 3 | 1 | 4 | 5 |
| Estrutura da fusão (palavras funcionais, ordem) | 2 | 3 | 2 | 4 | 3 | 4 |
| Escrita, segmentação, tokenização | 1 | 1 | 1 | 4 | 3 | 4 |
| Dados conversacionais abertos | 3 | 1 | 1 | 2 | 4 | 4 |
| Recursos e pesquisa em C.A. | 3 | 1 | 2 | 3 | 4 | 4 |
| Força do Qwen base no idioma | 2 | 1 | 1 | 1 | 3 | 3 |
| Impacto na UI | 1 | 1 | 1 | 3 | 2 | 4 |
| **Total (7–35)** | **15** | **9** | **11** | **18** | **23** | **28** |
| **Dificuldade** | média (referência) | baixa | baixa | média | alta | muito alta |

As notas são julgamento de engenharia, não medição. A primeira tarefa de cada idioma é uma rodada piloto pequena (núcleo de ~200 lemas, ouro de algumas centenas) para substituir a nota por números.

### 8.8 Ordem recomendada

1. **pt-BR** até a Fase 2 (prova o pipeline).
2. **Espanhol e inglês em paralelo:** o espanhol reaproveita quase tudo; o inglês traz o maior mercado e os melhores recursos.
3. **Mandarim**, quando houver decisão de produto sobre segmentação e escrita.
4. **Hindi**, com o perfil de gênero já maduro desde a Fase 1.
5. **Árabe**, por dialeto e com parceiros locais.

Francês (~310 milhões de falantes) é um candidato natural entre 2 e 3, com dificuldade próxima à do espanhol.

## 9. Restrições que valem em todas as fases

- **No aparelho:** o motor roda no iPad, sem serviço remoto nem custo por token em tempo de uso. Serviços remotos (professor, Jev) só na criação de dados, offline.
- **Privacidade:** dados de composição são sensíveis (saúde, intimidade, crianças). Nada sai do aparelho sem consentimento explícito e revogável.
- **Não censurar o usuário** (6.2). Filtrar apenas sugestões não pedidas.
- **Previsibilidade:** em C.A., a mesma ação deve dar o mesmo resultado. Decodificação determinística e cache por par; o modelo não deve “mudar de ideia” entre sessões sem motivo.
- **Fallback:** o `RuleEngine` (ou seu sucessor por léxico) continua respondendo quando o modelo falha, demora ou não carrega.

## 10. Riscos e perguntas em aberto

- O 1.7B quantizado cabe no orçamento de latência e memória dos iPads-alvo? Medir na Fase 0 com o 0.6B e extrapolar.
- Zonas como faixas de probabilidade mudam o comportamento visível do app; validar com usuários antes de trocar a regra binária.
- Quem define e revisa o vocabulário nuclear em pt-BR? Parceria com fonoaudiólogos é pré-requisito da Fase 1.
- Licenças de corpora e de saídas do professor para uso comercial.
- Ética do estudo com usuários de C.A. (comitê, responsáveis, acessibilidade do próprio consentimento).
- Um adaptador por idioma ou um multilíngue?
- Voz: fora do escopo hoje, mas o árabe (vogais omitidas) e o mandarim (tons) mostram que a escolha do motor afeta a síntese futura.

## 11. Referências (conferir versões e licenças)

**Modelos e treino**
- Hu, E. et al. (2021). *LoRA: Low-Rank Adaptation of Large Language Models*. arXiv:2106.09685.
- Dettmers, T. et al. (2023). *QLoRA: Efficient Finetuning of Quantized LLMs*. arXiv:2305.14314.
- Rafailov, R. et al. (2023). *Direct Preference Optimization: Your Language Model is Secretly a Reward Model*. arXiv:2305.18290.
- Hinton, G., Vinyals, O. & Dean, J. (2015). *Distilling the Knowledge in a Neural Network*. arXiv:1503.02531.
- Qwen Team (2025). *Qwen3 Technical Report*. arXiv:2505.09388.
- Apple. MLX e mlx-lm / mlx-swift-lm (github.com/ml-explore).
- TypeSafe. Documentação do Jev (docs.typesafe.ai).

**C.A. e vocabulário nuclear**
- Banajee, M., Dicarlo, C. & Buras Stricklin, S. (2003). Core vocabulary determination for toddlers. *Augmentative and Alternative Communication*, 19(2), 67–73.
- Beukelman, D., Jones, R. & Rowan, M. (1989). Frequency of word usage by nondisabled peers in integrated preschool classrooms. *Augmentative and Alternative Communication*, 5(4), 243–248.
- Project Core, Center for Literacy and Disability Studies, UNC (Universal Core vocabulary).
- Trnka, K. et al. (2007). The effects of word prediction on communication rate for AAC. *NAACL-HLT 2007* (short papers).

**Recursos linguísticos**
- MacWhinney, B. (2000). *The CHILDES Project: Tools for Analyzing Talk*. Lawrence Erlbaum.
- Lison, P. & Tiedemann, J. (2016). OpenSubtitles2016: Extracting large parallel corpora from movie and TV subtitles. *LREC 2016*.
- Nivre, J. et al. (2020). Universal Dependencies v2: An evergrowing multilingual treebank collection. *LREC 2020*.
- McCarthy, A. et al. (2020). UniMorph 3.0: Universal Morphology. *LREC 2020*.
- Alencar, L., Cuconato, B. & Rademaker, A. (2018). MorphoBr: an open source large-coverage full-form lexicon for morphological analysis of Portuguese. *Texto Livre*, 11(3).
- Muniz, M., Nunes, M. G. V. & Laporte, É. (2005). UNITEX-PB, a set of flexible language resources for Brazilian Portuguese (DELAF-PB). *Workshop em Tecnologia da Informação e da Linguagem Humana (TIL)*.
- Taulé, M., Martí, M. A. & Recasens, M. (2008). AnCora: Multilevel annotated corpora for Catalan and Spanish. *LREC 2008*.
- Kakwani, D. et al. (2020). IndicNLPSuite: Monolingual corpora, evaluation benchmarks and pre-trained multilingual language models for Indian languages. *Findings of EMNLP 2020*.
- Obeid, O. et al. (2020). CAMeL Tools: An open source Python toolkit for Arabic natural language processing. *LREC 2020*.
- Bouamor, H. et al. (2018). The MADAR Arabic dialect corpus and lexicon. *LREC 2018*.
- Eberhard, D., Simons, G. & Fennig, C. (eds.). *Ethnologue: Languages of the World* (edição de 2025): números de falantes.
