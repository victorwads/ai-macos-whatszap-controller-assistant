# História do Projeto (pt-BR)

Eu sempre gostei de tecnologia, mas esse projeto não nasceu de "vontade de programar". Ele nasceu de um cansaço bem específico: o cansaço de ver a vida passando, a saúde pedindo cuidado, e o trabalho passando por cima mesmo assim. E eu indo junto. No automático.

Então, se você está lendo isso, já vou avisando: essa é uma história pessoal. Ela não é um texto técnico. É a história do meu assistente. E, de certa forma, é a história do que eu precisei virar para conseguir continuar funcionando quando eu não estava conseguindo.

## 1. Quando a vida fica grande demais

Teve uma época em que eu percebi uma coisa meio cruel: o trabalho consegue engolir a gente com uma eficiência absurda. E ele não engole só o tempo. Ele engole a saúde, engole a pausa, engole o "eu resolvo isso depois".

Só que tem coisas que não esperam. E saúde é uma dessas coisas.

Para quem nunca precisou encontrar um médico novo pelo convênio, pode parecer frescura. Mas quem já passou por isso sabe. É uma guerra. Você abre o site do convênio, pega uma lista, e aí começa:

- metade dos números não funciona
- o médico não atende mais
- o lugar mudou
- a secretária diz "não fazemos isso"
- ou atende, mas o horário mais próximo é daqui a dois meses

E tem dias em que você gasta quatro, cinco, seis horas. Não é exagero. É isso mesmo: o seu dia indo embora em ligação e tentativa. E no final, o mais triste é que muitas vezes você desiste, não porque não quer se cuidar, mas porque não dá. Simplesmente não dá. Você está cansado, você tem coisa para fazer, você está no limite.

## 2. A fase do assistente humano (e a vergonha boa de admitir que eu precisava)

Em algum momento, quando eu estava ganhando bem, eu contratei um amigo. Era tipo uma hora, uma hora e meia por dia. E eu lembro de pensar: "isso não é abuso". Porque a minha cabeça já estava meio programada para sentir culpa de pedir ajuda.

Eu pagava o que eu conseguia pagar. E eu sei que ele merecia mais. Só que o combinado era honesto: uma hora por dia. O trabalho dele era simples e, ao mesmo tempo, extremamente necessário para mim:

- organizar meus e-mails
- organizar calendário
- me lembrar de consultas
- e, principalmente, me ligar antes

E isso é uma coisa que parece pequena até acontecer: ele me ligava uma hora antes de um evento importante e dizia, com a firmeza que eu não tinha comigo mesmo: "agora você vai. Para o que você está fazendo. Vai para a consulta. Resolve."

Isso salvou coisas.

Só que também tinha o limite do óbvio: ele tinha o trabalho dele, a vida dele. E não dava para ele "virar meu cérebro externo" o tempo inteiro. E ele não tinha como ter acesso às coisas que eu mais precisava… tipo o meu WhatsApp.

E aí aconteceu a parte chata: eu fiquei sem dinheiro. Eu fiquei sem assistente. E eu fiquei sozinho com todas as pendências de novo.

## 3. Codex, e-mail, calendário… e a sensação de "cara, isso funciona"

Eu estava mexendo muito com Codex. Eu estava aprendendo, testando, brincando com projetos. E num desses momentos eu conectei o Codex com Gmail e calendário e falei: "beleza, você vai ser meu assistente em algumas coisas."

E ele até que se saiu bem. Do tipo:

- lê meus e-mails
- resume
- categoriza
- sugere ação

Só que tinha um problema gigante: custo.

Era quase deprimente. Para fazer coisas que, em tese, eram simples, ele consumia muita utilização. Às vezes um terço do limite de cinco horas. Às vezes metade. E eu ficava pensando: "isso é incrível, mas não é sustentável."

Na época, eu estava desempregado e usando programação como uma forma de estudar, de construir algo e, sinceramente, de me sentir vivo de novo. Então ver algo funcionar tão bem e ao mesmo tempo ser tão caro foi uma mistura muito estranha de empolgação e frustração.

E vale um detalhe importante: mesmo existindo integração com Gmail e calendário em outros contextos, dentro desse repositório essa parte ainda é uma das próximas evoluções. Eu queria primeiro resolver a dor mais aguda (WhatsApp) e criar um runtime local confiável. O resto viria depois.

E foi aí que veio o pensamento óbvio que estava faltando: "tá, e se isso funcionasse com WhatsApp?"

## 4. O WhatsApp como o buraco negro da minha vida

Eu lembro de pensar: "eu queria que alguém organizasse o meu WhatsApp."

Porque WhatsApp não é só chat. É vida administrativa. É convênio. É médico. É família. É trabalho. É o lugar onde os problemas aparecem primeiro.

No começo, eu fiz do jeito mais direto possível: dei acesso ao WhatsApp Desktop no macOS e usei as toolings de Accessibility para o assistente interagir.

Funcionava. Só que era pesado. Muito pesado.

O modelo tinha que entender UI. Entender janela. Entender onde clicar. Entender como o aplicativo se comporta. E, além disso, gastar token para interpretar um layout que muda.

Foi aí que eu pensei: eu não quero que o modelo esteja "olhando a tela". Eu quero que o modelo esteja trabalhando.

Então eu comecei a construir uma API (via MCP server) para transformar "WhatsApp" em ferramentas simples e objetivas:

- listar chats
- ler mensagens recentes
- enviar mensagens
- esperar eventos

Essa foi a origem do projeto.

E eu lembro de uma sensação muito específica desses primeiros dias: em dois, três dias de evolução com Codex, o negócio foi ficando bom rápido. Bom até demais.

E aí veio a segunda parte do soco: ficou caro demais rápido também.

## 5. A frase que mudou o projeto: "podia ser de graça"

Meu namorado falou uma frase que era tão óbvia que eu, no meu modo "eu preciso corrigir o que as pessoas falam", quase estraguei.

Ele falou: "nossa… podia ser de graça, né?"

Na hora eu fui quase corrigir… mas tudo isso foi na minha cabeça. Eu não cheguei a corrigir ele. Eu só *quase* fui, porque eu tenho esse modo meio automático de ser extremamente literal e querer ajustar a frase na hora.

E a parte bonita (e meio engraçada) é que eu estava falando com uma pessoa que eu amo muito — e que me entende desse jeito. Ele entende as nuances até da minha literalidade. Ele respeita isso. Ele não tenta me “consertar” nem pede para eu mudar.

Porque a verdade é: a IA em si *é* "de graça" no sentido de que ela é pública. Ela existe, dá para rodar, dá para usar modelos localmente — você não precisa necessariamente pagar para "ter IA".

O que não é de graça é a computação. O caro é processar. É pagar token na nuvem, ou pagar com hardware e energia na sua própria máquina.

Só que o ponto dele era outro. E ele estava certo:

O problema não é a IA "existir". O problema é processamento.

E aí rolou aquele mini silêncio. Tipo… “então… mas…” e *puf*.

Minha cabeça explodiu num jeito muito específico de Eureka. E a coisa que eu falei em voz alta, com uma empolgação quase infantil, foi:

"pera… talvez dê pra ser de graça."

Porque foi isso que a frase dele destravou: se o gargalo é compute, talvez eu consiga mover isso para rodar local, na minha máquina.

E foi tão um momento que a conversa meio que acabou ali — a gente estava no telefone, ele precisou voltar a trabalhar — mas eu fiquei. Eu fiquei com aquela gratidão meio absurda de saber que um comentário pequeno mudou completamente a minha motivação, a minha empolgação e, principalmente, a viabilidade desse projeto.

E aí eu lembrei do LM Studio. Eu não mexia com ele fazia quase um ano. E eu pensei: "pera… e se eu rodar isso local?"

## 6. LM Studio e o choque: modelos locais ficaram bons. Muito bons.

Eu tenho um Mac potente (M3 Max). E eu lembrava do passado: reasoning local era lento, parecia impraticável, era quase uma prova de paciência.

Só que eu abri o LM Studio de novo e foi um choque.

Os modelos ficaram absurdamente melhores por token. Eles fazem mais com menos. Pensam mais rápido. Fazem tool calling melhor. Não é só "tokens por segundo". É o que acontece dentro dos tokens.

E aí eu conectei o LM Studio no MCP e coloquei ele para usar WhatsApp.

Ele entendeu. Ele usou. Ele foi direto.

E eu pensei: "ok. Agora o problema é outro: memória."

## 7. Memória… e depois: dados sensíveis

Se ele vai ser um assistente de verdade, ele precisa lembrar coisas. Só que ele também precisa lembrar as coisas certas do jeito certo.

Porque eu percebi rápido uma coisa: eu não queria colocar CPF, número de convênio, cartão e informações pessoais dentro de uma memória "normal".

Se isso vai parar em mensagem, se isso vaza, se isso sai para qualquer lugar… acabou. É perigoso.

Então eu criei o conceito de dados sensíveis, separado. Com auditoria. Com motivo. Com um cuidado muito maior.

Eu queria que o assistente fosse útil, mas eu não queria que ele fosse irresponsável.

## 8. A decisão de ser Apple/macOS/Swift (e por que isso importa de verdade)

Eu quero deixar isso bem explícito: esse projeto não é "no Mac" por estética.

É porque Apple, hoje, está ficando conhecida por uma coisa que muda tudo: o Neural Engine e as capacidades nativas, com API pública.

E tem duas APIs que, para um assistente pessoal, são fundamentais:

- Speak (Text-to-Speech)
- Speech Recognition

Eu testei duas abordagens para speak:

1. o `say` no terminal (usa a voz configurada no sistema)
2. a API de Speech do Swift

E teve uma nuance que eu achei até engraçada: a API do Swift não deixa usar a voz da Siri. Por isso eu tinha feito o caminho do terminal.

Só que no final, em português, aconteceu uma coisa inesperada: a voz "Fernanda Enhanced" via API do Swift fala acento, cedilha e várias coisas que a Siri (System Voice) simplesmente engasga ou pronuncia errado dependendo do texto.

Então, apesar de a Siri soar mais "natural" em alguns momentos, a Fernanda Enhanced foi mais confiável para falar do jeito certo. E, para um assistente, ser confiável é mais importante do que ser bonito.

Ainda falta coisa na API pública: não tem Personal Voice, não tem tudo… mas o fato de existir uma base forte já foi um motivo enorme para esse projeto ser macOS-first.

E tem o ponto de compute: um Mac mais simples com 16GB já consegue rodar um modelo local. Ele vai ser mais lerdo. Vai ser mais burro. Mas roda.

No Windows, com 16GB e vídeo integrado, você não roda. Você precisa GPU. Você precisa VRAM. Você precisa de outra realidade.

E eu queria que esse projeto fosse viável para mais gente do mundo real, não só para quem tem uma placa de vídeo gigante.

## 9. Quando o WhatsApp Desktop começou a atrapalhar: WebView

Em algum momento, a integração nativa começou a me dar dor de cabeça.

Eu pensei: "tá… e se eu trouxer o WhatsApp Web para dentro do meu app?"

Foi uma virada importante. Porque colocar uma WebView com WhatsApp Web dentro do runtime significava:

- mais controle
- menos dependência externa
- menos interferência do usuário
- integração mais consistente

E aí o projeto deixou de ser "um server". Virou, de verdade, um runtime operacional. Um ambiente. Um lugar onde o assistente vive.

## 10. O momento em que eu percebi: isso não é só para mim

Depois que eu fiz o meu, eu comecei a mostrar para minha família. Para o meu namorado. Para a minha mãe.

E eu comecei a pensar: "ok… isso pode servir para outras pessoas."

Aí veio outra ideia: multi-perfis.

Não como uma "feature bonita". Mas por um motivo prático: eu posso hostear isso na minha máquina.

Na maior parte do tempo, o modelo fica ocioso. O que roda mais é polling do WhatsApp, estado, logs, essas coisas.

Então eu consigo, por exemplo, hostear um assistente para:

- meu namorado
- minha mãe
- meu padrasto

E a IA vai trabalhar em picos. Um recebe mensagem, o outro não recebe. E se os três receberem ao mesmo tempo, beleza, fica mais lento, mas ainda funciona.

Só que aí vem o problema óbvio: eles não estão na minha máquina. Eles não vão abrir LM Studio. Eles não vão ver logs. Eles não vão ver memórias. Eles não vão mexer em subjects.

E foi aí que eu pensei: "a gente vai precisar de um app mobile."

Porque, para virar produto de verdade, o assistente precisa ser gerenciável remotamente.

E é isso. Essa história não acabou. Ela está só começando. E eu vou continuar escrevendo conforme o projeto (e a minha vida) continuarem acontecendo.
