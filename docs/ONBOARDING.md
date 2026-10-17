# Onboarding — equipe que assume o TesteMetaWord

> **Leitores:** as pessoas da equipe que assume o projeto e os agentes de IA que elas usam (Claude Code, Codex, Cursor ou similares). A seção 2 é escrita para os agentes: ela diz como apresentar o projeto a cada pessoa na primeira interação.

## 1. De onde vem este repositório

- É um **protótipo de design de interação**, feito por um **Designer AI Prototyper** com programação agêntica (Claude Code). Não é uma base de produto pronta, e o autor não segue no projeto como engenheiro.
- O objetivo foi provar uma tese de interação para Comunicação Alternativa (C.A.) no iPad: compor frases fundindo palavras em Liquid Glass, com física orgânica, centro óptico e zonas de relevância. O protótipo também preparou o terreno para um motor de composição por modelo de linguagem local.
- **Nível de confiança do código:** foi escrito em grande parte por agentes e avaliado pelo autor **pelo comportamento** (simulador, capturas, testes), não por revisão de engenharia. Há testes de lógica e de interface; nenhum formatter ou linter foi executado; nada foi validado em iPad físico nem com usuários de C.A.

### 1.1 Intenção de design × escolha de implementação

O que está na coluna da esquerda é a tese do protótipo: mudar exige decisão explícita de alguém da equipe, de preferência conversando com o autor. A coluna da direita foi escolhida para viabilizar o protótipo e pode ser trocada livremente, seguindo o fluxo do `AGENTS.md`.

| Intenção de design (decidir antes de mudar) | Escolha de implementação (pode trocar) |
| --- | --- |
| Liquid Glass **nativo** do SwiftUI, sem simulação com blur/gradiente | `GlassEffectContainer(spacing: 32)`, tints, `glassEffectID` |
| Fusão como **mitose reversa**; sugestões **brotam** do resultado (mitose) | Tempos (0,2 s de convergência), impulsos radiais, crossfade |
| Intenção medida por **profundidade de sobreposição**, nunca por tempo (sem dwell) | Limiar de 45% da menor altura |
| **A composição fica parada durante o gesto** e só se reorganiza depois | Congelar a física enquanto há arrasto, seleção, par preparado ou fusão |
| **Centro óptico** (palavra recém-fundida) e **três zonas de atmosfera**: mais perto do foco, mais provável a fusão | Algoritmo de slots por zona, bisseção do raio, gaps 40/136/232 pt, constantes em `Physics.swift` |
| Composição **orgânica**, sem grade fixa; flutuação idle **sincronizada por família** | Órbita de 4 pt e 6 s, fase herdada |
| Erro é recuperável: **Undo** como divisão do resultado, long press, alternativa por toque | Histórico de estados completos |
| Acessibilidade: movimento reduzido, alvos legíveis durante o movimento | Implementação atual de `reduceMotion` |
| Motor de composição **local**, sem serviço remoto nem custo por token no uso | `RuleEngine`; Qwen3-0.6B + LoRA via mlx-lm em `ml/` |

## 2. Instruções para o agente de IA

### 2.1 Primeira interação com uma pessoa da equipe

Quando alguém abrir o projeto pela primeira vez, pedir contexto (“o que é isto?”, “por onde começo?”) ou não indicar que já conhece o projeto, ofereça o briefing abaixo **antes** de executar tarefas grandes.

1. **Leia, nesta ordem:**
   1. `AGENTS.md` (regras do projeto);
   2. este documento;
   3. `README.md` (uso, código, build, validação);
   4. `SPEC.md` (comportamento atual);
   5. `HANDOFF.md` (estado da última iteração);
   6. `future-HANDOFF.md`, só se o assunto for motor de composição, IA, escala ou idiomas;
   7. `ml/README.md`, só se o assunto for treino ou avaliação do modelo;
   8. `docs/GIT.md`, antes de qualquer commit.
2. **Confira o estado real:** `git status --short --branch` e `git log --oneline -10`. Se algo citado nos documentos não existir (arquivo, resultado, teste), diga isso no briefing em vez de supor.
3. **Entregue o briefing** com a estrutura da seção 2.3, em pt-BR, em no máximo uma tela.
4. **Pergunte** qual é o papel da pessoa (engenharia iOS, ML, design, produto, pesquisa) e adapte o próximo passo sugerido a esse papel.

### 2.2 Regras permanentes

- `SPEC.md` é o comportamento atual. `future-HANDOFF.md` é **prospecção**, não requisito: use-o para responder perguntas de roteiro e para propor trabalho, nunca como especificação a implementar sem decisão da equipe.
- Não altere uma **intenção de design** (tabela 1.1) por conta própria. Se uma tarefa a contradiz, aponte o conflito e peça decisão.
- **Segredos:** nunca leia, imprima nem commite `.env`. Cada pessoa cria o seu a partir de `.env.example`. A chave do Jev usada nos comparativos é do autor e não acompanha o repositório; quem precisar rodar `ml/evaluate_jev.py` obtém uma chave própria.
- Ao relatar resultados, separe sempre: **compilado**, **testado no simulador**, **validado em iPad físico**, **avaliado com usuário de C.A.** Não promova um nível ao outro.
- Mudou arrasto ou fusão? Valide o gesto completo (arrastar e soltar) em teste de interface.
- Não acrescente serviço remoto de IA, voz ou persistência sem que a equipe defina o experimento.
- Terminou uma tarefa que muda o estado do projeto? Atualize `HANDOFF.md`.

### 2.3 Estrutura do briefing

```markdown
**O que é:** <2–3 frases: protótipo de C.A. no iPad, fusão de palavras em Liquid Glass, motor local em preparação>
**Origem:** protótipo de design (Designer AI Prototyper + agentes); confiança de protótipo, não de produto.
**Funciona hoje:** <composição, fusão, sugestões, Undo, toque; o que os testes cobrem>
**Não validado:** <iPad físico, VoiceOver, desempenho, uso com C.A., motor por modelo no app>
**Intenção de design a preservar:** <3–5 itens da tabela 1.1 relevantes ao papel da pessoa>
**Como rodar:** <comandos de build/teste do README>
**Próximo passo sugerido para o seu papel:** <ver seção 4>
**Decisões que são da equipe:** <itens da seção 5 ainda abertos>
```

## 3. Estado na entrega (16/10/2026)

| Área | Estado | Onde ver |
| --- | --- | --- |
| Composição (zonas, física, órbitas, fusão, sugestões, Undo, toque, calibração) | Funciona no simulador; coberta por testes de lógica e de interface | `SPEC.md`, `README.md` (Validação), `docs/media/` |
| Motor de composição no app | `RuleEngine` com 25 palavras fixas; contrato `CompositionEngine` pronto para outro motor | `TesteMetaWord/CompositionEngine.swift` |
| Motor por modelo local | Qwen3-0.6B + LoRA treinado no Mac (rodadas 1 e 2); **não integrado ao app** | `ml/README.md`, `ml/results/` |
| Comparativo com Jev (TypeSafe) | Feito: bom como juiz de validade offline, fraco em zonas; remoto, então fora do app | `future-HANDOFF.md` (seção 1), `ml/evaluate_jev.py` |
| Não validado | iPad físico, VoiceOver, teclado/trackpad, desempenho do vidro a cada frame, alvos em movimento em uso de C.A., movimento reduzido no dedo | `README.md`, `HANDOFF.md` |
| Fora da v1 | Pinça, zona de sumiço, persistência, voz | `AGENTS.md` |

Capturas do simulador:
- `docs/media/zones-initial.png`: foco no centro, zonas e halos;
- `docs/media/zones-fusion-frames.png`: sequência da fusão e do Undo;
- `docs/media/zones-after-fusion.png`: composição depois da fusão.

Os pesos treinados (`ml/adapters/`) não são versionados. Para reproduzir, treine de novo (rodada 2: cerca de 1 h num Mac M4).

## 4. Primeiro passo por papel

| Papel | Comece por |
| --- | --- |
| Engenharia iOS | Build e testes do `README.md`; rode no simulador e faça querer + ir; leia `ContentView.swift` e `Physics.swift`. Primeira entrega útil: rodar em **iPad físico** e medir o desempenho do vidro. |
| ML | `ml/README.md`; reproduza a avaliação da rodada 2; depois, a Fase 0 do `future-HANDOFF.md` (`LocalModelEngine` com MLX Swift e latência no iPad). |
| Design | Rode no simulador ou no iPad e compare com a tabela 1.1; as pendências de design estão em `HANDOFF.md` (tint/fundo do vidro, hierarquia da frase, membrana, glifo do Undo). |
| Produto ou pesquisa | `future-HANDOFF.md` inteiro; as decisões da seção 5 abaixo; parceria com fonoaudiólogos é pré-requisito da Fase 1. |

## 5. Decisões que passam a ser da equipe

- **Laboratório ou produto?** Nome, bundle identifier, repositório, equipe de assinatura, CI.
- **Fluxo Git:** manter o do laboratório (`main` + `exp/<nome>`, sem PR; `docs/GIT.md`) ou adotar PR e CI.
- **Convenções de trabalho com agentes.** O protótipo foi feito sob estas regras (do ambiente do autor, não versionadas no repositório), pensadas para um projeto **sem usuários reais**:
  1. documentação primeiro (README, SPEC), depois os testes mínimos de alto sinal, depois a menor implementação, depois a limpeza;
  2. sem compatibilidade retroativa nem migração de dados;
  3. substituir o que muda pela forma mais simples e atualizar todos os chamadores na mesma mudança;
  4. não manter abstrações “por via das dúvidas”;
  5. dizer explicitamente quando uma checagem (testes, formatter, linter) não foi executada.

  Com usuários reais, as regras 2 e 3 deixam de valer. A equipe decide o que adota e registra no `AGENTS.md`.
- **Motor de composição:** seguir ou não o roteiro do `future-HANDOFF.md`, a começar pela Fase 0.
- **Pesquisa com usuários de C.A.:** ética, consentimento, parceiros (fonoaudiólogos).
- **Decisões em aberto do `AGENTS.md`:** pinça, zona de sumiço, persistência, voz.

## 6. Mapa dos documentos

| Documento | Para quê |
| --- | --- |
| `AGENTS.md` | Regras do projeto para pessoas e agentes; conceito, decisões da v1, fluxo Git |
| `CLAUDE.md` | Faz o Claude Code carregar o `AGENTS.md` |
| `docs/ONBOARDING.md` | Este documento: transição para a equipe e briefing dos agentes |
| `README.md` | Uso, mapa do código, build/testes, resultado da validação |
| `SPEC.md` | Comportamento atual, constantes e critérios |
| `HANDOFF.md` | Estado da última iteração e pendências |
| `future-HANDOFF.md` | Prospecção: vocabulário aberto, dados, treino, avaliação, outros idiomas |
| `ml/README.md` | Workspace do modelo local: decisões, comandos, resultados por rodada |
| `docs/GIT.md` | Comandos do fluxo Git do laboratório |
