# Fontes primárias verificadas

* [Topologia real por núcleo — Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getlogicalprocessorinformationex)
* [PROCESS_INFORMATION_CLASS — Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ne-processthreadsapi-process_information_class): ProcessMemoryPriority é a enum Win32, não a classe NT 39. A nova versão não altera prioridade de memória.
* [SetPriorityClass — Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setpriorityclass): background begin/end só no próprio processo; removidos. AboveNormal é uma classe suportada, não ganho garantido.
* [MMCSS — Microsoft](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service): adesão por thread via AvSetMmThreadCharacteristics; não existe associação genérica automática de executáveis a task customizada.
* [Flip model — Microsoft](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model): apresentação moderna em janela pode atingir Independent Flip, sem inferência universal de atraso por DWM.
* [GameDVR policy — Microsoft](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr): política de gravação; não promete FPS.
* [Powercfg — Microsoft](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options): consulta e escrita de índices de energia. O alias IDLEDISABLE foi confirmado pelo `powercfg /aliases` local (GUID 5d76a2ca-e8c0-402f-a133-2158492d58ad); suporte é consultado por `/qh`, não presumido de uma URL de tuning. Nenhuma magnitude de benefício é inferida desse alias.
* [Chromium flags — Google](https://github.com/GoogleChrome/chrome-launcher/blob/main/docs/chrome-flags-for-tools.md): retirar throttling/backgrounding não reduz trabalho de background.
* [PresentMon console — Intel](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md): esquemas, métricas, hotkey com sufixo e seleção de streams.

Documentação de API fundamenta funcionamento, não magnitude de ganho. Data da revisão: 30/10/2026. Nenhuma dessas fontes substitui baseline neste hardware.
