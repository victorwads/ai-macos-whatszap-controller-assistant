# Backlog (WhatsApp Assistant)

Arquivo em: `/Users/DevData/victorwads/GitRepos/Personal/AssistantMCPServer/backlog.md`

Instrução: antes de qualquer commit relacionado a itens deste backlog, validar que o build está funcionando usando `scripts/check_build_and_restart.sh`.

Legenda de valor:
- `V5 - Altíssimo`: bug crítico ou valor muito alto para o cliente
- `V4 - Alto`: importante para a experiência ou para a arquitetura
- `V3 - Médio`: relevante, mas não bloqueia o uso principal
- `V2 - Baixo`: melhoria útil, porém não essencial
- `V1 - Muito baixo`: ideia futura ou ajuste opcional

Legenda de risco de desenvolvimento:
- `R1 - Baixíssimo`: implementação direta e pouco sensível
- `R2 - Baixo`: mudança local com pouco impacto colateral
- `R3 - Médio`: exige coordenação entre partes do sistema
- `R4 - Alto`: mexe em fluxo importante ou integrações sensíveis
- `R5 - Muito alto`: pode afetar comportamento central ou exigir migração cuidadosa

Legenda de risco da feature:
- `R1 - Baixíssimo`: feature isolada e com baixo impacto se falhar
- `R2 - Baixo`: efeito colateral limitado e fácil de perceber
- `R3 - Médio`: pode afetar operação real ou exigir fallback claro
- `R4 - Alto`: pode alterar comportamento sensível, mensagens ou automação
- `R5 - Muito alto`: pode expor dados, quebrar fluxo central ou exigir controles fortes

Score de Execução:
- Fórmula base: `valor / ((risco de desenvolvimento * 1.5) + risco da feature)`
- Fator de desbloqueio: `1 + (quantidade de itens que dependem dele / 10)`
- Score final: `score base * fator de desbloqueio`
- Quanto maior o score, melhor candidato para executar agora.
- Bugs críticos de perda de dados/mensagens podem furar a fila mesmo com score menor.

Este arquivo reúne ideias e melhorias para retomarmos depois. Cada item fica separado por uma linha `---`.

Exemplo de prompts para manutenção:
- Execute as alterações do item `## X) Xxxxx Xxx Xxxxx Xxxxx` do arquivo `backlog.md`.
- Pode remover do backlog e comitar as alterações e o backlog inteiro. (após permissão explicita para remover do backlog)

---

## 1) Encontrar chat que não aparece na lista inicial

Valor: `V4 - Alto`
Risco de Desenvolvimento: `R4 - Alto`
Risco da Feature: `R3 - Médio`
Score de Execução: `0.44`

**Descrição**  
Quando a conversa não estiver visível na lista principal do app, o agente deve conseguir pesquisar o nome ou número na barra de busca do WhatsApp Web/Desktop, validar o resultado e abrir o chat certo antes de seguir com a ação.

**Dependências**  
- `Configuração de seletores via YAML com auto-update`

**Por que isso entra no backlog**  
É um fluxo mais complexo e frágil, porque depende de busca, seleção de resultado, validação de ambiguidade e sincronização do contexto do chat antes do envio.

---

## 2) Arquivar conversa

Valor: `V3 - Médio`
Risco de Desenvolvimento: `R3 - Médio`
Risco da Feature: `R3 - Médio`
Score de Execução: `0.40`

**Descrição**  
Adicionar a capacidade de arquivar uma conversa específica para manter o conjunto de chats ativos mais enxuto e organizado. O comportamento padrão do WhatsApp de reabrir o chat quando chegam mensagens novas continua valendo.

**Dependências**  
- `Configuração de seletores via YAML com auto-update`

**Evidências/seletores observados na row**  
- `data-testid="list-item-0"` identifica a linha da conversa.
- `data-testid="cell-frame-container"`, `data-testid="cell-frame-title"` e `data-testid="cell-frame-primary-detail"` organizam a estrutura visual da row.
- `data-testid="last-msg-status"` expõe o preview/status da última mensagem.
- `data-testid="status-dblcheck"` indica o estado de entrega/leitura do último envio.
- `aria-label="Conversa fixada"` mostra que há ao menos um estado de pin visível nessa row.
- Neste trecho específico ainda não apareceu o menu ou botão de arquivar; isso precisa ser encontrado em outro nível da UI ou em outro estado do DOM.

**Por que isso entra no backlog**  
É uma melhoria útil para controle de contexto e limpeza da lista de conversas, com uma implementação relativamente direta em comparação com o fluxo de busca/resolução de chat.

---

## 3) Bloqueio e desbloqueio da WebView

Valor: `V4 - Alto`
Risco de Desenvolvimento: `R3 - Médio`
Risco da Feature: `R3 - Médio`
Score de Execução: `0.52`

**Descrição**  
Adicionar um ícone de bloqueio/desbloqueio ao lado do título do WhatsApp para controlar a interação com a WebView. No modo bloqueado, a WebView fica travada para o usuário, com viewport fixo em `1080p` e mantendo `80%` de escala. No modo desbloqueado, a WebView volta a usar o tamanho disponível da janela, também com `80%` de escala.

**Dependências**  
- `Nenhuma`

**Comportamento desejado**  
- Mostrar um ícone de bloqueado/desbloqueado ao lado do título.
- Quando bloqueado, impedir interação do usuário com a WebView.
- Quando desbloqueado, permitir interação normal e ajustar o viewport ao tamanho da janela.
- Exibir um helper/tooltip avisando que ao desbloquear o pooling de mensagens vai parar.

**Por que isso entra no backlog**  
Isso controla melhor o modo de uso entre automação e interação manual, além de recuperar um comportamento que já existia na primeira versão.

---

## 4) Configuração de seletores via YAML com auto-update

Valor: `V4 - Alto`
Risco de Desenvolvimento: `R4 - Alto`
Risco da Feature: `R4 - Alto`
Score de Execução: `0.40`

**Descrição**  
Externalizar os seletores e IDs usados no parse do WhatsApp Web para um arquivo `YAML` versionado. Esse arquivo deve ser bundlado no app como padrão, mas o runtime pode baixar uma versão mais recente via uma URL configurável nas Settings. Se a URL estiver vazia, o app usa apenas o `YAML` embutido e não tenta atualizar.

**Dependências**  
- `Nenhuma`

**Regras desejadas**  
- O `YAML` precisa carregar metadados como data da versão e versão do schema.
- Enquanto a versão do schema for compatível, o app pode atualizar só o `YAML` sem exigir atualização do binário.
- Se o schema mudar, a atualização precisa ser feita no app nativo.
- Toda a lógica de parsing atual do WhatsApp Web deve deixar de depender de IDs hardcoded espalhados no código e passar a consultar essa configuração centralizada.
- O `YAML` deve permitir múltiplas alternativas por seletor, para cobrir mudanças de DOM/HTML sem quebrar o fluxo.

**Por que isso entra no backlog**  
Isso reduz o acoplamento com o HTML atual do WhatsApp Web e facilita manter o app funcionando quando a interface mudar, sem precisar lançar uma nova versão para toda alteração pequena de seletor.

---

## 5) Corrigir ordenação e metadados da lista de chats

Valor: `V5 - Altíssimo`
Risco de Desenvolvimento: `R4 - Alto`
Risco da Feature: `R2 - Baixo`
Score de Execução: `0.56`

**Descrição**  
Corrigir o bug em que a listagem de chats fica desordenada quando o WhatsApp Web retorna apenas textos como `quinta-feira` ou horários soltos em vez de uma data completa da última mensagem. O objetivo é encontrar, se existir, a origem correta da data/hora real da última mensagem em formato estruturado, mapear esse valor para algo ordenável, preferencialmente `ISO string`, e usar isso tanto na listagem visual quanto no repositório/ordenação interna.

**Dependências**  
- `Configuração de seletores via YAML com auto-update`

**Contexto observado**  
- No exemplo atual, a row expõe `lastMessageAtText`, `lastMessageDirection`, `lastMessagePreview` e `lastMessageStatus`, mas não mostra um timestamp estruturado.
- O texto exibido pode servir para UI, mas não é confiável para ordenação consistente.
- Se o HTML ou metadado interno trouxer um timestamp em `ISO`, esse campo deve ser o candidato principal para armazenar e ordenar.

**Problema observado**  
- Em `list_chats`, o campo da última mensagem às vezes aparece só como texto humano, sem `ISO date`.
- Quando a última mensagem não traz data completa, a ordenação quebra ou fica parcial.
- Alguns metadados da última mensagem ainda precisam ser recuperados corretamente, incluindo o status da última mensagem.
- A versão nativa já parecia tratar melhor esses dados, mas no Web isso ainda não está estável.

**Objetivo**  
- Encontrar a origem correta da data da última mensagem, se ela existir em algum metadado interno do WhatsApp Web.
- Usar essa data estruturada para ordenar os chats no repositório e na listagem visual.
- Garantir que o status da última mensagem também seja preenchido corretamente.

**Por que isso entra no backlog**  
Sem uma data real e estruturada, a lista não consegue ser ordenada por recência com confiança, o que afeta diretamente a experiência e a leitura operacional dos chats. Como `ISO string` ordena bem lexicograficamente, ela também simplifica a lógica de sorting quando esse dado estiver disponível.

---

## 6) Exposição externa para app mobile e controle por API

Valor: `V2 - Baixo`
Risco de Desenvolvimento: `R5 - Muito alto`
Risco da Feature: `R5 - Muito alto`
Score de Execução: `0.18`

**Descrição**  
Externalizar parte da experiência do assistente para uma aplicação mobile ou outra interface cliente, permitindo que o usuário controle a máquina que roda o MCP server e o assistente de forma remota. A ideia é que tanto o fluxo de falar com o cliente quanto o fluxo do cliente responder possam ser acessados por essa camada externa.

**Dependências**  
- `Nenhuma`

**Capacidades desejadas**  
- Expor uma API para integração com app mobile ou outro cliente externo.
- Permitir iniciar, acompanhar e controlar interações sem depender só da máquina local.
- Suportar envio e recebimento de áudio, incluindo gravação e reprodução no dispositivo remoto quando fizer sentido.
- Permitir reconhecimento de voz no lado do cliente, com possibilidade de usar recursos nativos do iPhone/Android ou um backend como `Whisper`.
- Manter a máquina principal como origem do contexto, mas com interface externa para operação e resposta.

**Por que isso entra no backlog**  
Isso amplia o alcance do assistente para fora da máquina local e abre caminho para uma experiência mais portátil, principalmente para controlar conversas e áudios pelo celular.

---

## 7) `wait_for_event` não pode consumir pendências

Valor: `V5 - Altíssimo`
Risco de Desenvolvimento: `R3 - Médio`
Risco da Feature: `R3 - Médio`
Score de Execução: `0.67`

**Descrição**  
Corrigir o bug em que a toll `wait_for_event` está marcando como resolvidas ou “handled” conversas que ainda não tiveram suas mensagens lidas pelo assistente. o evento `wait_for_event` deve ser read only e não alterar nada. O que realmente retorna as não lidas e marca elas como lidas, é o `list_recent_messages` e `wait_for_chat_message`.
Hoje o assistente esta perdendo as mensagens pois ele chama o `wait_for_event` para listar os chats não lidos, mas esse endpoint esta marcando eles como lidos, então quando o `list_recent_messages` é chamado, ele não encontra mais nada para ler e vem vazio.

**Dependências**  
- `Nenhuma`

**Regra desejada**  
- `wait_for_event` apenas informa quais chats têm pendência.
- Somente `list_recent_messages` ou `wait_for_chat_message` pode marcar mensagens como `handled` para um chat específico.
- A limpeza de lido/handled deve ocorrer apenas depois do pull real das mensagens do chat.
- A resposta do `wait_for_event` precisa trazer o nome do evento, como `prompt_from_cliente` ou `unhandled_chat`, e não apenas um tipo genérico como `chat_messages`. pois as vezes o evento não é sobre mensagens, mas sobre outra coisa, como um prompt do cliente ou um evento de sistema.
- O payload do evento deve ser explícito o suficiente para distinguir o que aconteceu sem depender de inferência externa.

**Por que isso entra no backlog**  
Esse bug quebra o fluxo de consumo do assistente e faz perder mensagens antes da leitura real, então a responsabilidade de “consumir” precisa ficar restrita ao endpoint certo.

---

## 8) Indicador de "digitando" durante o processamento

Valor: `V3 - Médio`
Risco de Desenvolvimento: `R3 - Médio`
Risco da Feature: `R4 - Alto`
Score de Execução: `0.35`

**Descrição**  
Adicionar uma melhoria de UX para mostrar que o assistente está processando uma conversa depois de receber e ler as mensagens recentes. A ideia é ativar um estado visual de `digitando` no chat enquanto o sistema pensa e prepara a resposta, para que a pessoa que está esperando veja que o assistente está ativo.

**Dependências**  
- `Nenhuma`

**Comportamento desejado**  
- Quando `list_recent_messages` for chamado para um chat específico, o chat pode entrar em estado de `digitando`.
- Enquanto a resposta estiver sendo processada, o indicador pode variar de forma sutil, como se o WhatsApp Web estivesse alternando caracteres na área de escrita.
- O estado deve ser usado como feedback visual temporário durante o processamento.
- Quando o envio da resposta terminar, o estado de `digitando` deve ser removido.

**Por que isso entra no backlog**  
Isso não muda a lógica principal do assistente, mas melhora bastante a percepção de responsividade para quem está aguardando a resposta.

---

## 9) Estados de presente e ausente

Valor: `V4 - Alto`
Risco de Desenvolvimento: `R4 - Alto`
Risco da Feature: `R3 - Médio`
Score de Execução: `0.44`

**Descrição**  
Adicionar um estado global para a aplicação entre `presente` e `ausente`, para que o assistente saiba como se comportar quando o usuário estiver na frente do computador ou não. Quando estiver `presente`, o assistente pode usar o fluxo de `speak_to_client` normalmente. Quando estiver `ausente`, ele deve evitar interromper o usuário e responder de forma mais assíncrona, registrando as pendências para revisão posterior.

**Dependências**  
- `Nenhuma`

**Comportamento desejado**  
- Permitir alternar manualmente entre `presente` e `ausente`.
- Quando estiver `presente`, o assistente pode falar normalmente com o usuário e usar o `speak_to_client`.
- Quando estiver `ausente`, o assistente deve informar que o usuário está ocupado e que o assunto será atualizado depois.
- O `ask_to_client` deve ter `timeout`, para evitar ficar esperando indefinidamente uma resposta.
- Se o usuário não responder dentro do `timeout`, o assistente deve assumir comportamento de ausência e seguir o fluxo apropriado.
- Esse estado pode aproveitar o mesmo repositório de pendências já usado para as conversas a responder.

**Por que isso entra no backlog**  
Isso permite que o assistente adapte o comportamento ao contexto real do usuário, melhorando tanto a experiência ao vivo quanto a operação 24 horas por dia.

---

## 10) Testes automatizados de integração com MCP server

Valor: `V5 - Altíssimo`
Risco de Desenvolvimento: `R3 - Médio`
Risco da Feature: `R2 - Baixo`
Score de Execução: `0.77`

**Descrição**  
Criar uma suíte de testes automatizados em Swift para validar o fluxo real da aplicação contra o MCP server reiniciado. A ideia é cobrir testes de integração que chamem as tools do servidor e validem os comportamentos principais da integração com WhatsApp Web.

**Dependências**  
- `Menu LM Studio no Server para iniciar e pausar o agente`

**Estratégia desejada**  
- Usar um grupo fixo de testes no WhatsApp, com nome como `testes integrados`, para executar as validações.
- Esse chat deve servir como ambiente controlado para envio de mensagem, listagem de mensagens e outras tools críticas.
- Os testes de integração devem agir como um client do MCP server, chamando as tools depois que o servidor for reiniciado.
- Como o WhatsApp Web não permite múltiplas instâncias independentes, os testes devem rodar contra a mesma instância ativa após o build e reinício do servidor.
- Cada fluxo de integração existente ou nova criado no projeto deve ter cobertura de teste automatizado correspondente. ex.: listagem de chats, leitura de mensagens, envio de mensagens, arquivamento, pesquisa de chat, etc.

**Notas técnicas**  
- O melhor encaixe é evoluir o `scripts/check_build_and_restart.sh`, porque ele já centraliza gerar o projeto, buildar e reiniciar o app; esse fluxo pode passar a opcionalmente executar a suíte de integração logo após o restart.
- Se os testes não ficarem acoplados ao script, o `README` precisa explicar com clareza como rodá-los e em que momento eles entram no processo de manutenção.
- O prompt de implementação deve deixar explícito que, ao concluir essa feature, o `README` precisa ser atualizado para refletir o novo fluxo.
- Antes de codar, confirmar os nomes reais de targets, alvos de teste e arquivos envolvidos, porque essa estrutura pode ter mudado desde o planejamento.

**Regra de desenvolvimento desejada**  
- Não permitir commit de manutenção relevante sem executar os testes automatizados aplicáveis e validar que passaram.
- Os prompts e instruções de manutenção devem exigir a execução dos testes antes do commit.
- A regra operacional ideal é: build, restart e execução dos testes no mesmo fluxo sempre que possível.

**Por que isso entra no backlog**  
Isso reduz regressões, formaliza o uso do servidor como alvo de testes e dá mais confiança para evoluir a integração sem quebrar o fluxo real do WhatsApp.

---

## 11) Visual de chat para a tela de voice client

Valor: `V3 - Médio`
Risco de Desenvolvimento: `R2 - Baixo`
Risco da Feature: `R1 - Baixíssimo`
Score de Execução: `0.75`

**Descrição**  
Reimaginar a tela de `voice client voice` para exibir os registros em formato de conversa, em vez de uma lista linear simples. A estrutura de dados continua a mesma, com cada linha representando um registro de `voice client`, mas o visual passa a parecer um chat com as mensagens como balões.

**Dependências**  
- `Nenhuma`

**Comportamento desejado**  
- Quando for apenas `speak`, a mensagem aparece à esquerda, como fala do assistente para o usuário.
- Quando houver `ask_to_client` com resposta, a mensagem do assistente aparece à esquerda e a resposta do usuário aparece à direita.
- Quando for `ask_to_client` sem resposta, a caixa de resposta deve continuar aparecendo logo abaixo da pergunta.
- Se houver várias perguntas pendentes, elas continuam aparecendo em sequência, sem mudar a lógica atual de agrupamento.
- A mudança é apenas visual, sem alterar a estrutura de dados ou a ordem funcional dos registros.

**Notas técnicas**  
- A mudança deve ficar concentrada na camada SwiftUI da `ClientVoiceScreen`, porque hoje a tela já separa `pendingAsks` e `historyEvents` e renderiza com `List`/`Section`.
- O modelo base já existe em `ClientVoiceEvent`, então a nova apresentação pode reaproveitar `kind`, `prompt`, `text`, `transcript` e `askStatus` sem mudar a persistência.
- O painel de resposta pendente embaixo da pergunta deve continuar funcionando como hoje; a alteração é de composição visual, não de regra de negócio.
- Antes de implementar, confirmar se o nome da tela, subviews e estados auxiliares continuam os mesmos, para não acoplar a mudança a arquivos que possam ter sido renomeados.

**Por que isso entra no backlog**  
Isso melhora bastante a leitura da conversa de voz, deixando a tela mais natural e próxima de um chat real, sem exigir mudança estrutural no fluxo atual.

---

## 12) Menu `LM Studio` no `Server` para iniciar e pausar o agente

Valor: `V5 - Altíssimo`
Risco de Desenvolvimento: `R1 - Baixíssimo`
Risco da Feature: `R1 - Baixíssimo`
Score de Execução: `2.60`

**Descrição**  
Adicionar um novo item de menu na aba `Server`, chamado `LM Studio`, para controlar a sessão operacional do assistente diretamente pela aplicação Swift. Esse painel deve permitir iniciar o agente com o prompt de início de trabalho, pausar/cancelar a sessão ativa e iniciar novamente do zero, descartando o contexto anterior.

Hoje o fluxo ainda depende de o cliente abrir o LM Studio manualmente, carregar o modelo, criar o chat e disparar o prompt inicial. Esse item existe justamente para tirar essa operação manual do caminho e deixar a aplicação Swift assumir o controle básico do lifecycle.

**Dependências**  
- `Nenhuma`

**Comportamento desejado**  
- Exibir um botão para iniciar o agente sem exigir abertura manual do LM Studio.
- Exibir um botão para pausar/cancelar a sessão ativa.
- Ao iniciar novamente depois de pausar, a sessão deve começar limpa, sem reaproveitar contexto anterior.
- O item deve ficar dentro da navegação existente da aba `Server`, junto das demais telas operacionais.

**Por que isso entra no backlog**  
Isso remove a necessidade de operar o LM Studio manualmente para subir ou parar o agente, e funciona como uma camada de controle simples, isolada e praticamente sem risco sobre o código atual.

---

## 13) Contrato de humanização pós-tool

Valor: `V4 - Alto`
Risco de Desenvolvimento: `R4 - Alto`
Risco da Feature: `R3 - Médio`
Score de Execução: `0.44`

**Descrição**  
Alterar o contrato de `speak_to_client`, `send_message` e `ask_to_client` para que o runtime em Swift receba contexto adicional de forma explícita antes de humanizar a saída. O agente principal continua decidindo normalmente, mas passa mais dados na requisição MCP, como motivo, contexto, memórias relevantes e preferências de comunicação. Depois disso, o runtime encaminha a mensagem para um modelo separado de humanização, sem reasoning, que apenas reescreve o texto final.

Hoje a comunicação já existe, mas ainda mistura decisão operacional com linguagem final. Essa camada nova serve para separar melhor as responsabilidades e permitir que o sistema seja mais humano sem exigir que o agente principal carregue toda a estratégia de estilo no mesmo prompt.

**Dependências**  
- `Menu LM Studio no Server para iniciar e pausar o agente`

**Comportamento desejado**  
- Essa feature depende da existência da tela/runtime de controle do LM Studio.
- O agente principal não deve precisar saber que existe uma etapa posterior de humanização.
- O runtime deve separar o fluxo operacional do fluxo social, tratando a humanização como uma etapa stateless.
- O modelo de humanização deve receber apenas o contexto necessário para ajustar tom e naturalidade.
- O `system prompt` principal do projeto vai precisar ser ajustado para refletir esse novo fluxo em duas camadas.
- `speak_to_client`, `send_message` e `ask_to_client` vão precisar de mais campos obrigatórios para alimentar a etapa de humanização com contexto suficiente.

**Por que isso entra no backlog**  
Isso diminui o acoplamento entre decisão operacional e linguagem social, deixando o sistema mais modular e permitindo que o assistente fale de forma mais natural sem misturar decisão com estilo.

---

## 14) Visualização dos eventos SSE do LM Studio

Valor: `V4 - Alto`
Risco de Desenvolvimento: `R3 - Médio`
Risco da Feature: `R2 - Baixo`
Score de Execução: `0.62`

**Descrição**  
Expor, no runtime do macOS e também em uma futura interface mobile, uma visualização bonita e legível dos eventos emitidos pelo stream SSE do LM Studio durante `POST /api/v1/chat` com `stream: true`. A ideia é mostrar o que o agente está fazendo enquanto responde, como carregamento de modelo, processamento do prompt, reasoning, tool calls, erros e fechamento da resposta.

**Comportamento desejado**  
- Mostrar a sequência dos eventos em tempo real, como uma timeline ou painel de atividade.
- Destacar `reasoning`, `tool_call` e `message` com visual diferente.
- Associar ícones diferentes para cada tipo de tool ou evento.
- Exibir quando o modelo está carregando, processando prompt, pensando ou aguardando ferramentas.
- Tornar essa visão acessível para quem estiver remoto e não puder olhar o LM Studio diretamente.

**Dependências**  
- `Menu LM Studio no Server para iniciar e pausar o agente`
- `Exposição externa para app mobile e controle por API`

**Comportamento desejado**  
- O runtime pode continuar sendo a fonte de observabilidade, com o app mobile apenas espelhando essa visão.
- A implementação deve confirmar os nomes reais dos eventos e a forma final do payload antes de consolidar a UI.

**Por que isso entra no backlog**  
Isso melhora bastante a transparência do runtime, ajuda a diagnosticar o que o agente está fazendo e leva para a interface remota uma visão que hoje só existe no LM Studio.

---
