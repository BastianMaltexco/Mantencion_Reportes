const picker = document.getElementById('attachments');
const preview = document.getElementById('file-preview');
if (picker && preview) picker.addEventListener('change', () => {
  preview.replaceChildren();
  [...picker.files].forEach(file => {
    const card = document.createElement('div'); card.className = 'rounded-lg border border-slate-200 p-2 text-xs text-slate-600';
    if (file.type.startsWith('image/')) { const image = document.createElement('img'); image.className = 'mb-2 h-20 w-full rounded object-cover'; image.src = URL.createObjectURL(file); card.append(image); }
    const name = document.createElement('p'); name.className = 'truncate'; name.textContent = file.name; card.append(name); preview.append(card);
  });
});

const areaSelect = document.getElementById('area_id');
const sectionSelect = document.getElementById('section_id');
const machinerySelect = document.getElementById('machinery_id');
const fillSelect = (select, items, placeholder) => {
  select.replaceChildren(new Option(placeholder, ''));
  items.forEach(item => select.add(new Option(item.name, item.id)));
  select.disabled = false;
};
const loadOptions = async (url, select, placeholder) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error('No se pudo cargar el catálogo.');
  fillSelect(select, await response.json(), placeholder);
};
if (areaSelect && sectionSelect && machinerySelect) {
  loadOptions('/api/areas', areaSelect, 'Seleccione un área').catch(() => fillSelect(areaSelect, [], 'No se pudieron cargar áreas'));
  areaSelect.addEventListener('change', async () => {
    sectionSelect.disabled = true; machinerySelect.disabled = true;
    sectionSelect.replaceChildren(new Option('Cargando secciones...', ''));
    machinerySelect.replaceChildren(new Option('Seleccione una sección', ''));
    if (!areaSelect.value) return;
    try { await loadOptions(`/api/sections?area_id=${encodeURIComponent(areaSelect.value)}`, sectionSelect, 'Seleccione una sección'); }
    catch (_) { fillSelect(sectionSelect, [], 'No se pudieron cargar secciones'); }
  });
  sectionSelect.addEventListener('change', async () => {
    machinerySelect.disabled = true; machinerySelect.replaceChildren(new Option('Cargando maquinarias...', ''));
    if (!sectionSelect.value) return;
    try { await loadOptions(`/api/machineries?section_id=${encodeURIComponent(sectionSelect.value)}`, machinerySelect, 'Seleccione una maquinaria'); }
    catch (_) { fillSelect(machinerySelect, [], 'No se pudieron cargar maquinarias'); }
  });
}

document.querySelectorAll('[data-evidence-key]').forEach(group => {
  group.addEventListener('change', event => {
    const key = group.dataset.evidenceKey;
    const input = document.getElementById(`evidence-${key}`);
    const wrapper = document.getElementById(`evidence-wrap-${key}`);
    const required = event.target.value === group.dataset.evidenceAnswer;
    wrapper.classList.toggle('hidden', !required);
    input.required = required;
    if (!required) input.value = '';
  });
});

document.querySelectorAll('input[name^="liters_"]').forEach(input => {
  input.max = '749'; input.step = '1';
  input.addEventListener('input', () => {
    input.setCustomValidity(Number(input.value) > 749 ? 'El máximo permitido es 749 litros.' : '');
  });
});
