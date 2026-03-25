# Guião Final da Apresentação

---

## Slide 1. Introdução

Olá, eu sou o Afonso e vou apresentar o trabalho individual que consistia em adicionar observabilidade ao nopCommerce, uma plataforma de e-commerce open-source.
---

## Slide 2. The Flow
Começando pelo flow escolhido, este foi o flow da Order. Apesar de parecer simples quando estamos a usar o site. Ao analisar o código percebi que existem diversas operações feitas então acabei por dividir em fases internas: `prepare`, `payment`, `persist_order`, `move_items` e `finalize`.

Foram essas diferentes fazes que decidi observar com mais detalhe, visto que é um processo complexo, que envolve várias partes do sistema e que é crítico para o negócio. 
---

## Slide 3. Architecture

Antes de instrumentar o checkout,foi necessário entender a estrutura do sistema, composta pelas layers `Nop.Core`, `Nop.Services`, `Nop.Data` e `Nop.Web`. Focando no flow escolhido, é possível ver que o pedido de Confirmação é processado em várias etapas. O `CheckoutController` recebe e valida parte do pedido, o `OrderProcessingService` faz as operações principais, o `EntityRepository` lida com operações de persistência e o `IEventPublisher` propaga efeitos laterais dentro do sistema.


A arquitetura do nopCommerce ajudou porque já existe uma separação relativamente clara de responsabilidades. A layer Nop.Web trata da interação HTTP e da composição das páginas e endpoints. A layer Nop.Services concentra a lógica de negócio e a orquestração dos casos de uso, que neste trabalho foi o ponto mais importante. A layer Nop.Data abstrai o acesso à base de dados, e a Nop.Core reúne entidades de domínio, settings e algumas abstrações transversais usadas pelo resto da aplicação.

No checkout, isto traduz-se num fluxo em camadas. O pedido entra pelo CheckoutController, mas esse controller não faz sozinho o trabalho pesado. Ele prepara contexto, valida pré-condições e delega a operação principal ao OrderProcessingService. Depois, durante a execução, esse serviço comunica com outros serviços de negócio, aciona persistência através do repositório e dispara eventos para o resto do sistema. Ou seja, a ordem não nasce num ponto isolado; ela resulta da colaboração entre várias layers e componentes.

Isto foi importante para a observabilidade porque me mostrou onde existiam boundaries reais. Em vez de instrumentar métodos arbitrários, consegui focar-me em pontos que já tinham significado arquitetural: o boundary do serviço para o span principal, o repositório para a persistência, e o event publisher para os efeitos laterais. Isso tornou a instrumentação mais cirúrgica e mais alinhada com a estrutura original do sistema

---

## Slide 4. Instrumentation Organization

Nesta parte, a pergunta central foi: onde é que a instrumentação deve viver? Nem toda a observabilidade deve ser colocada no mesmo sítio, porque diferentes tipos de sinal precisam de diferentes níveis de contexto. Por isso, acabei por usar uma organização híbrida.

Para o span principal do checkout, usei um decorator sobre `IOrderProcessingService`, através de `ObservedOrderProcessingService`. Esse decorator cria o span `nop.checkout.place_order`, que representa a operação de negócio que realmente me interessa. Isto foi importante porque o tracing automático do ASP.NET Core vê o request HTTP, mas não vê por si só o conceito de “colocar uma encomenda”.

Já a instrumentação por fases ficou inline no `OrderProcessingService`. A razão é que a própria orquestração do checkout já vive em `PlaceOrderAsync`, e é aí que existem as fronteiras reais das fases, o contexto local, os resultados, as exceções e os `reason_code` mais úteis. Tentar empurrar tudo isso para decorators adicionais teria exigido mais abstrações e mais refatoração do que o assignment justificava.

Para manter consistência, concentrei a semântica comum em helpers partilhados, sobretudo em `CheckoutTelemetry`. Aí ficam os nomes das métricas, as tags, os resultados, os helpers de spans e o vocabulário comum da observabilidade. Assim, o decorator, o controller e o serviço podem partilhar a mesma linguagem sem duplicar lógica.

---

## Slide 5. Privacy Strategy

Uma preocupação importante neste trabalho foi garantir que a observabilidade não se tornava um risco de privacidade. No checkout circulam dados potencialmente sensíveis, como emails, moradas, campos de pagamento e outros detalhes do cliente. Por isso, a solução não podia ser simplesmente exportar tudo para Grafana e Tempo e depois esperar que ninguém olhasse para os campos errados.

A estratégia escolhida foi centralizar a sanitização. Em vez de tentar lembrar-me em cada ponto de instrumentação do que é seguro ou não exportar, implementei um processador, `SensitiveActivitySanitizingProcessor`, que corre antes da exportação. Esse processador remove tags sensíveis de forma centralizada no pipeline de OpenTelemetry. Esta abordagem foi preferível porque é mais consistente, mais fácil de manter e muito menos propensa a erro humano do que uma sanitização manual espalhada por vários ficheiros.


---

## Slide 6. Traces & Metrics

Ao nível de tracing, a peça central é o span `nop.checkout.place_order`, que representa a operação de negócio completa do checkout. Abaixo dele ficam os spans das fases internas: `prepare`, `payment`, `persist_order`, `move_items` e `finalize`. Isto permite seguir o percurso da order dentro do backend e perceber em que ponto o fluxo está lento ou falha.

Além disso, também há spans adicionais em boundaries importantes, como o `EntityRepository`, para operações de base de dados, e instrumentação do sistema de eventos, para publicação interna. Isto ajuda a ligar a lógica de negócio à persistência e aos side effects sem encher o trace com ruído excessivo.

Quanto às métricas, as principais para o checkout são `nop.checkout.stage_completions_total`, `nop.checkout.stage_duration_ms`, `nop.checkout.completion_time_ms` e `nop.checkout.repository_write_duration_ms`.

A métrica `nop.checkout.stage_completions_total` conta quantas vezes cada fase termina com sucesso ou com falha. É a métrica mais útil para calcular failure rate por stage e para perceber rapidamente onde o flow está a quebrar.

A métrica `nop.checkout.stage_duration_ms` mede a duração de cada fase do checkout. Serve para responder à pergunta “qual é a fase que está lenta?”, e por isso é especialmente útil para percentis como p95.

A métrica `nop.checkout.completion_time_ms` mede o tempo total da operação `place_order`, ou seja, a latência end-to-end do backend a partir do momento em que a encomenda é realmente processada. É a melhor métrica para ter uma visão global da performance do checkout.

Por fim, `nop.checkout.repository_write_duration_ms` mede a latência das escritas no repositório durante o checkout. Esta métrica ajuda a separar problemas de persistência de problemas de lógica de negócio. Se o `persist_order` estiver lento, consigo perceber se a causa está realmente na base de dados ou noutra parte da fase.

---

## Slide 7. Trade Offs

O primeiro trade-off foi adicionar observabilidade sem grandes refatorações. O assignment pede uma abordagem cirúrgica, e eu tentei respeitar isso. Em vez de reestruturar o nopCommerce à volta da observabilidade, aproveitei boundaries que já existiam. Usei um decorator onde fazia sentido e mantive a instrumentação inline onde o contexto de negócio já estava presente.

Outro trade-off foi entre detalhe e ruído. Se eu tentasse instrumentar todos os métodos auxiliares, o resultado seriam traces cheios de spans pouco úteis e um dashboard difícil de interpretar. Por isso, escolhi focar-me nas fases principais do checkout e em alguns boundaries fortes, como persistência e eventos. Isso sacrifica alguma granularidade, mas melhora bastante a clareza operacional.

Houve também um trade-off entre melhor diagnóstico e uma mudança localizada do modelo de falhas. Inicialmente, algumas falhas apareciam apenas como `validation`, o que era demasiado genérico. Depois refinei alguns casos importantes, como `minimum_order_total` e `minimum_order_subtotal`, através de `CheckoutValidationException`, para tornar o dashboard mais acionável. Ainda assim, mantive a mudança limitada, porque não queria transformar trabalho de observabilidade num redesenho global do modelo de exceções do nopCommerce.

Por fim, houve um trade-off entre gerar sinal útil para a demo e fazer um load test verdadeiramente exaustivo. O objetivo do k6 não foi benchmark completo da plataforma, mas sim gerar tráfego suficiente para validar os painéis, os traces e os cenários de falha escolhidos. Isso está alinhado com o assignment, que diz explicitamente que o load test não precisa de ser sofisticado; precisa apenas de tornar o dashboard significativo.

---

## Parte Final. Demo do Dashboard

Na demo, eu começaria por mostrar o dashboard de topo para baixo, porque ele foi organizado para apoiar uma sequência de diagnóstico. Primeiro olho para `Checkout Failure Rate (%)`, `Checkout Completion Latency p95` e `Checkout Completion Latency p50`. Estes três painéis dão logo uma leitura rápida: o sistema está a falhar, está a degradar, ou está saudável mas sob carga normal?

Depois passaria para `Checkout Stage Latency`, porque esse painel ajuda a perceber se a lentidão está concentrada numa fase específica do backend. Se, por exemplo, a latência aumentar no `payment`, isso aponta para um problema diferente de um aumento no `persist_order` ou no `move_items`. A possibilidade de alternar o percentile da latência por stage também ajuda a comparar o comportamento típico com outliers.

Se a suspeita cair no `persist_order`, o passo seguinte é olhar para `Checkout Repository Write Latency p95`. Esse painel é útil porque separa duas hipóteses que de outra forma ficam misturadas: base de dados lenta ou lógica de negócio lenta dentro da mesma fase. Se a latência do `persist_order` sobe e a latência das escritas no repositório também sobe, isso sugere um bottleneck mais próximo da persistência. Se o `persist_order` sobe mas o repositório se mantém estável, então o problema está mais provavelmente na lógica do serviço, nos side effects ou noutra parte da fase.

A seguir mostraria `Successful vs Failed Completions Over Time` e `Checkout Failure Rate Over Time`. Estes painéis são úteis porque mostram quando começou a degradação e se o sistema está a deslocar-se de sucesso para falha sob carga. Em vez de olhar só para um valor atual, consigo perceber tendência ao longo do tempo.

Depois entraria em `Checkout Failures by Reason Code`. Este é um dos painéis mais úteis para diagnóstico porque traduz um problema abstrato num tipo de falha mais concreto. Se o que domina for `minimum_order_total`, o engenheiro sabe que está perante uma regra de validação específica. Se o problema aparecer como `payment_declined` ou outro `reason_code`, a investigação muda logo de direção.

Em seguida, passaria para os traces: `Latest Checkout Traces` e `Latest Error Checkout Traces`. A utilidade aqui é sair do sinal agregado do dashboard e entrar num caso real. Ao abrir um trace, consigo mostrar o span principal `nop.checkout.place_order`, depois as fases internas e, se necessário, a ligação a repositório e eventos. Isso ajuda a explicar que o dashboard não é apenas decorativo; ele leva a evidência concreta.

Por fim, fecharia a demo nos traces recentes, porque é aí que consigo passar do sintoma agregado do dashboard para a evidência concreta de uma execução. Isto ajuda a mostrar que o dashboard não é apenas visual; ele serve mesmo como ponto de entrada para investigação.

Se quiseres uma frase de fecho para a demo, eu diria isto: o valor do trabalho não está só em ter métricas e traces, mas em conseguir passar de uma pergunta genérica como “há problema?” para uma resposta concreta como “a falha está na fase prepare, com este reason code, e consigo abrir o trace correspondente”.

---

## Nota Importante Sobre os Slides Atuais

Há dois pontos no `POWERPOINT.pdf` que eu corrigiria antes da apresentação final:

- no slide de `Instrumentation Organization`, a terceira card diz “single file”, mas na implementação real a lógica está repartida principalmente entre `NopTelemetry` e `CheckoutTelemetry`; eu reformularia isso para “shared telemetry layer”
- no slide de `Trade Offs`, a numeração está inconsistente e falta um quarto item preenchido; eu usaria como quarto trade-off: `Generating Useful Demo Signal Without Turning the Load Test Into a Benchmark`
