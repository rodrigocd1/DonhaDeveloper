import { createElement } from "@lwc/engine-dom";
import PesquisasPortal from "c/pesquisasPortal";
import listarEmpreendimentos from "@salesforce/apex/PesquisasPortalController.listarEmpreendimentos";

jest.mock(
  "@salesforce/apex/PesquisasPortalController.listarEmpreendimentos",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () => Promise.resolve();

describe("c-pesquisas-portal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("carrega os empreendimentos e apresenta a página inicial", async () => {
    listarEmpreendimentos.mockResolvedValue([
      { id: "a0101", nome: "Residencial A" }
    ]);
    const element = createElement("c-pesquisas-portal", {
      is: PesquisasPortal
    });
    document.body.appendChild(element);

    await flushPromises();
    await flushPromises();

    expect(listarEmpreendimentos).toHaveBeenCalledTimes(1);
    expect(element.shadowRoot.querySelector("c-pesquisas-home")).not.toBeNull();
    expect(element.shadowRoot.querySelector("lightning-spinner")).toBeNull();
  });

  it("mostra erro seguro quando o carregamento falha", async () => {
    listarEmpreendimentos.mockRejectedValue({
      body: { message: "Serviço indisponível" }
    });
    const element = createElement("c-pesquisas-portal", {
      is: PesquisasPortal
    });
    document.body.appendChild(element);

    await flushPromises();
    await flushPromises();

    const error = element.shadowRoot.querySelector('[role="alert"]');
    expect(error.textContent).toContain("Serviço indisponível");
  });
});
