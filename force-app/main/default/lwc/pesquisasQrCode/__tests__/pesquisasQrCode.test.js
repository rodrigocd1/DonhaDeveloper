import { createElement } from "@lwc/engine-dom";
import PesquisasQrCode from "c/pesquisasQrCode";
import { loadScript } from "lightning/platformResourceLoader";

jest.mock(
  "lightning/platformResourceLoader",
  () => ({ loadScript: jest.fn() }),
  { virtual: true }
);

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-pesquisas-qr-code", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    delete window.qrcode;
    jest.clearAllMocks();
  });

  it("gera imagem local para a URL informada", async () => {
    const generator = {
      addData: jest.fn(),
      make: jest.fn(),
      createDataURL: jest.fn(() => "data:image/gif;base64,QR")
    };
    loadScript.mockResolvedValue();
    window.qrcode = jest.fn(() => generator);
    const element = createElement("c-pesquisas-qr-code", {
      is: PesquisasQrCode
    });
    element.value = "https://example.com/checkin";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(generator.addData).toHaveBeenCalledWith(
      "https://example.com/checkin"
    );
    expect(element.shadowRoot.querySelector("img").getAttribute("src")).toBe(
      "data:image/gif;base64,QR"
    );
  });

  it("mostra fallback quando a biblioteca falha", async () => {
    loadScript.mockRejectedValue(new Error("falha"));
    const element = createElement("c-pesquisas-qr-code", {
      is: PesquisasQrCode
    });
    element.value = "https://example.com/checkin";
    document.body.appendChild(element);
    await flushPromises();
    await flushPromises();

    expect(element.shadowRoot.querySelector('[role="status"]')).not.toBeNull();
  });
});
