/*
 * switch.{cc,hh} -- element routes packets to one output of several
 * Eddie Kohler
 *
 * Copyright (c) 2000 Mazu Networks, Inc.
 *
 * This software is being provided by the copyright holders under the GNU
 * General Public License, either version 2 or, at your discretion, any later
 * version. For more information, see the `COPYRIGHT' file in the source
 * distribution.
 */

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif
#include "switch.hh"
#include "confparse.hh"
#include "error.hh"

Switch *
Switch::clone() const
{
  return new Switch;
}

void
Switch::notify_noutputs(int n)
{
  set_noutputs(n);
}

int
Switch::configure(const Vector<String> &conf, ErrorHandler *errh)
{
  _output = 0;
  if (cp_va_parse(conf, this, errh,
		  cpOptional,
		  cpInteger, "active output", &_output,
		  0) < 0)
    return -1;
  if (_output >= noutputs())
    _output = -1;
  return 0;
}

void
Switch::push(int, Packet *p)
{
  if (_output < 0)
    p->kill();
  else
    output(_output).push(p);
}

String
Switch::read_param(Element *e, void *)
{
  Switch *sw = (Switch *)e;
  return String(sw->_output) + "\n";
}

int
Switch::write_param(const String &in_s, Element *e, void *, ErrorHandler *errh)
{
  Switch *sw = (Switch *)e;
  String s = cp_uncomment(in_s);
  if (!cp_integer(s, &sw->_output))
    return errh->error("Switch output must be integer");
  if (sw->_output >= sw->noutputs())
    sw->_output = -1;
  sw->set_configuration(String(sw->_output));
  return 0;
}

void
Switch::add_handlers()
{
  add_read_handler("switch", read_param, (void *)0);
  add_write_handler("switch", write_param, (void *)0);
}

EXPORT_ELEMENT(Switch)
